mod config;
mod recorder;
mod tray;

use std::time::Duration;

use anyhow::{Result, bail};
use gstreamer as gst;
use ksni::TrayMethods;
use tokio::sync::{mpsc, watch};

use config::Config;
use recorder::{Finished, Recording};
use tray::Tray;

const BUS_NAME: &str = "org.mislooms.Recorder";
const OBJECT_PATH: &str = "/org/mislooms/Recorder";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Idle,
    Starting,
    Recording,
    Stopping,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Status::Idle => "idle",
            Status::Starting => "starting",
            Status::Recording => "recording",
            Status::Stopping => "stopping",
        }
    }
}

#[derive(Debug)]
pub enum Cmd {
    Toggle,
    Start,
    Stop,
    OpenFolder,
    Quit,
    /// El pipeline de la grabación con este id terminó.
    Finished(u64, Finished),
}

#[tokio::main]
async fn main() -> Result<()> {
    let arg = std::env::args().nth(1);
    match arg.as_deref() {
        None | Some("daemon") => run_daemon().await,
        Some(cmd @ ("toggle" | "start" | "stop" | "status")) => send_command(cmd).await,
        Some(other) => {
            eprintln!("comando desconocido: {other}\nuso: mis-looms [daemon|toggle|start|stop|status]");
            std::process::exit(2);
        }
    }
}

/// Cliente: envía el comando al daemon por D-Bus (para atajos de Hyprland).
async fn send_command(cmd: &str) -> Result<()> {
    let conn = zbus::Connection::session().await?;
    let method = match cmd {
        "toggle" => "Toggle",
        "start" => "Start",
        "stop" => "Stop",
        _ => "Status",
    };
    let reply = conn.call_method(Some(BUS_NAME), OBJECT_PATH, Some(BUS_NAME), method, &()).await;
    match reply {
        Ok(msg) => {
            if method == "Status" {
                println!("{}", msg.body().deserialize::<String>()?);
            }
            Ok(())
        }
        Err(zbus::Error::MethodError(name, ..)) if name.as_str() == "org.freedesktop.DBus.Error.ServiceUnknown" => {
            bail!("el daemon no está corriendo; inícialo con `mis-looms`")
        }
        Err(e) => Err(e.into()),
    }
}

struct DbusService {
    tx: mpsc::UnboundedSender<Cmd>,
    status: watch::Receiver<Status>,
}

#[zbus::interface(name = "org.mislooms.Recorder")]
impl DbusService {
    fn toggle(&self) {
        let _ = self.tx.send(Cmd::Toggle);
    }
    fn start(&self) {
        let _ = self.tx.send(Cmd::Start);
    }
    fn stop(&self) {
        let _ = self.tx.send(Cmd::Stop);
    }
    fn status(&self) -> String {
        self.status.borrow().as_str().to_owned()
    }
}

async fn run_daemon() -> Result<()> {
    gst::init()?;
    let config = Config::load()?;
    let (tx, mut rx) = mpsc::unbounded_channel::<Cmd>();
    let (status_tx, status_rx) = watch::channel(Status::Idle);

    let _dbus = zbus::connection::Builder::session()?
        .name(BUS_NAME)?
        .serve_at(OBJECT_PATH, DbusService { tx: tx.clone(), status: status_rx })?
        .build()
        .await
        .map_err(|e| anyhow::anyhow!("¿ya hay otro mis-looms corriendo? ({e})"))?;

    let tray = Tray { status: Status::Idle, tx: tx.clone() }.spawn().await?;

    let mut recording: Option<(u64, Recording)> = None;
    let mut next_id = 0u64;

    let set_status = |status: Status| {
        let _ = status_tx.send(status);
        let tray = tray.clone();
        async move {
            tray.update(|t| t.status = status).await;
        }
    };

    while let Some(cmd) = rx.recv().await {
        let status = *status_tx.borrow();
        let cmd = match (cmd, status) {
            (Cmd::Toggle, Status::Idle) => Cmd::Start,
            (Cmd::Toggle, Status::Recording) => Cmd::Stop,
            (cmd, _) => cmd,
        };
        match cmd {
            Cmd::Start if status == Status::Idle => {
                set_status(Status::Starting).await;
                next_id += 1;
                let id = next_id;
                let finish_tx = tx.clone();
                let on_finish = move |result| {
                    let _ = finish_tx.send(Cmd::Finished(id, result));
                };
                match Recording::start(&config, on_finish).await {
                    Ok(rec) => {
                        println!("grabando en {}", rec.path.display());
                        recording = Some((id, rec));
                        set_status(Status::Recording).await;
                    }
                    Err(e) => {
                        eprintln!("no se pudo iniciar: {e:#}");
                        notify("No se pudo iniciar la grabación", &format!("{e:#}"));
                        set_status(Status::Idle).await;
                    }
                }
            }
            Cmd::Stop if status == Status::Recording => {
                if let Some((id, rec)) = &recording {
                    set_status(Status::Stopping).await;
                    rec.stop();
                    // Si el EOS nunca llega, no dejamos la app colgada.
                    let (id, tx) = (*id, tx.clone());
                    tokio::spawn(async move {
                        tokio::time::sleep(Duration::from_secs(15)).await;
                        let _ = tx.send(Cmd::Finished(id, Err(anyhow::anyhow!("timeout esperando fin del archivo"))));
                    });
                }
            }
            Cmd::Finished(id, result) if recording.as_ref().is_some_and(|(cur, _)| *cur == id) => {
                let (_, rec) = recording.take().expect("comprobado arriba");
                let path = rec.path.clone();
                rec.close().await;
                match result {
                    Ok(()) => {
                        println!("guardado: {}", path.display());
                        notify("Grabación guardada", &path.display().to_string());
                    }
                    Err(e) => {
                        eprintln!("la grabación falló: {e:#}");
                        notify("La grabación falló", &format!("{e:#}"));
                    }
                }
                set_status(Status::Idle).await;
            }
            Cmd::OpenFolder => {
                let _ = std::fs::create_dir_all(&config.output_dir);
                let _ = std::process::Command::new("xdg-open").arg(&config.output_dir).spawn();
            }
            Cmd::Quit => {
                if let Some((_, rec)) = recording.take() {
                    rec.stop();
                    tokio::time::sleep(Duration::from_secs(2)).await;
                    rec.close().await;
                }
                break;
            }
            _ => {}
        }
    }
    Ok(())
}

fn notify(summary: &str, body: &str) {
    let (summary, body) = (summary.to_owned(), body.to_owned());
    std::thread::spawn(move || {
        let result = notify_rust::Notification::new()
            .appname("Mis Looms")
            .summary(&summary)
            .body(&body)
            .icon("media-record")
            .show();
        if let Err(e) = result {
            eprintln!("no se pudo mostrar la notificación: {e}");
        }
    });
}
