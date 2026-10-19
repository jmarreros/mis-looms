mod api;
mod cli;
mod config;
mod media;
mod recorder;
mod tray;
mod ui;
mod uploader;

use std::collections::HashSet;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use anyhow::{Result, bail};
use gstreamer as gst;
use ksni::TrayMethods;
use tokio::sync::{mpsc, watch};
use tokio_util::sync::CancellationToken;

use config::Config;
use recorder::{Capture, Finished, Recording};
use tray::Tray;
use uploader::{UploadError, UploadState, Uploader};

const BUS_NAME: &str = "org.mislooms.Recorder";
const OBJECT_PATH: &str = "/org/mislooms/Recorder";
const COUNTDOWN_SECONDS: u32 = 3;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Status {
    Idle,
    /// Esperando al portal (selector de pantalla).
    Starting,
    /// Segundos que faltan para empezar.
    Countdown(u32),
    Recording,
    Paused,
    /// Entre pulsar «finalizar» y tener el MP4 cerrado.
    Stopping,
}

impl Status {
    fn as_str(self) -> &'static str {
        match self {
            Status::Idle => "idle",
            Status::Starting => "starting",
            Status::Countdown(_) => "countdown",
            Status::Recording => "recording",
            Status::Paused => "paused",
            Status::Stopping => "stopping",
        }
    }
}

/// Todo lo que la bandeja y la interfaz necesitan para dibujarse.
#[derive(Debug, Clone)]
pub struct Snapshot {
    pub status: Status,
    /// Tiempo grabado en tramos anteriores a la última pausa.
    pub recorded: Duration,
    /// Inicio del tramo actual; `None` en pausa o sin grabar.
    pub since: Option<Instant>,
    /// 0–100 mientras se sube.
    pub upload: Option<u8>,
    pub pending_uploads: bool,
    pub last_link: Option<String>,
    pub config: Config,
}

impl Snapshot {
    pub fn elapsed(&self) -> Duration {
        self.recorded + self.since.map(|s| s.elapsed()).unwrap_or_default()
    }
}

#[derive(Debug, Clone, Copy)]
pub enum Option_ {
    SystemAudio,
    Countdown,
    OpenLink,
    ShowPanel,
}

pub enum Cmd {
    Toggle,
    Start,
    Stop,
    TogglePause,
    Discard,
    CancelCountdown,
    OpenFolder,
    CopyLastLink,
    OpenSettings,
    RetryUploads,
    CancelUpload,
    Set(Option_, bool),
    PanelPosition(i32, i32),
    ServerUrl(String),
    Quit,
    // Internos
    CaptureReady(u64, Result<Capture>),
    Tick(u64),
    Begin(u64),
    /// El pipeline de la grabación con este id terminó.
    Finished(u64, Finished),
    UploadProgress(String, f64),
    UploadDone(String, Result<String, UploadError>),
}

/// Mensajes del controlador a la interfaz GTK.
pub enum UiEvent {
    Snapshot(Snapshot),
    OpenSettings,
    Quit,
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        None | Some("daemon") => run_daemon(),
        Some(cmd @ ("toggle" | "start" | "stop" | "pause" | "status" | "ajustes")) => {
            tokio::runtime::Runtime::new()?.block_on(send_command(cmd))
        }
        Some("subir") => cli::upload(args.get(1).map(PathBuf::from)),
        Some("reanudar") => cli::resume(),
        Some(other) => {
            eprintln!(
                "comando desconocido: {other}\n\
                 uso: mis-looms [daemon | toggle | start | stop | pause | status | ajustes | subir ARCHIVO.mp4 | reanudar]"
            );
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
        "pause" => "TogglePause",
        "ajustes" => "OpenSettings",
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
    fn toggle_pause(&self) {
        let _ = self.tx.send(Cmd::TogglePause);
    }
    fn open_settings(&self) {
        let _ = self.tx.send(Cmd::OpenSettings);
    }
    fn status(&self) -> String {
        self.status.borrow().as_str().to_owned()
    }
}

/// El controlador corre en tokio; la interfaz GTK, en el hilo principal.
fn run_daemon() -> Result<()> {
    gst::init()?;
    let config = Config::load()?;
    let runtime = tokio::runtime::Runtime::new()?;
    // Abrir la app desde el lanzador con el daemon ya en marcha: mostrar los Ajustes.
    if runtime.block_on(send_command("ajustes")).is_ok() {
        return Ok(());
    }
    let (tx, rx) = mpsc::unbounded_channel::<Cmd>();
    let (ui_tx, ui_rx) = async_channel::unbounded::<UiEvent>();

    let controller = {
        let tx = tx.clone();
        runtime.block_on(async move { Controller::new(config, tx, ui_tx).await })?
    };
    runtime.spawn(controller.run(rx));
    ui::run(tx, ui_rx, runtime.handle().clone());
    // La interfaz termina cuando el controlador manda `UiEvent::Quit`.
    runtime.shutdown_timeout(Duration::from_secs(2));
    Ok(())
}

struct Controller {
    config: Config,
    tx: mpsc::UnboundedSender<Cmd>,
    ui: async_channel::Sender<UiEvent>,
    tray: ksni::Handle<Tray>,
    status_tx: watch::Sender<Status>,
    _dbus: zbus::Connection,

    status: Status,
    recorded: Duration,
    since: Option<Instant>,
    next_id: u64,
    capture: Option<(u64, Capture)>,
    recording: Option<(u64, Recording)>,
    discarding: bool,
    quitting: bool,

    /// Subida en curso: id del estado y cómo cancelarla.
    upload: Option<(String, CancellationToken)>,
    upload_progress: Option<u8>,
    /// Fallaron en esta sesión: no se reintentan solas.
    failed: HashSet<String>,
    /// Grabaciones de esta sesión: al subirse abren el navegador.
    open_after: HashSet<String>,
    last_link: Option<String>,
}

impl Controller {
    async fn new(config: Config, tx: mpsc::UnboundedSender<Cmd>, ui: async_channel::Sender<UiEvent>) -> Result<Self> {
        let (status_tx, status_rx) = watch::channel(Status::Idle);
        let dbus = zbus::connection::Builder::session()?
            .name(BUS_NAME)?
            .serve_at(OBJECT_PATH, DbusService { tx: tx.clone(), status: status_rx })?
            .build()
            .await
            .map_err(|e| anyhow::anyhow!("¿ya hay otro mis-looms corriendo? ({e})"))?;
        let mut this = Self {
            tray: Tray::new(tx.clone()).spawn().await?,
            config,
            tx,
            ui,
            status_tx,
            _dbus: dbus,
            status: Status::Idle,
            recorded: Duration::ZERO,
            since: None,
            next_id: 0,
            capture: None,
            recording: None,
            discarding: false,
            quitting: false,
            upload: None,
            upload_progress: None,
            failed: HashSet::new(),
            open_after: HashSet::new(),
            last_link: None,
        };
        this.publish().await;
        Ok(this)
    }

    fn snapshot(&self) -> Snapshot {
        Snapshot {
            status: self.status,
            recorded: self.recorded,
            since: self.since,
            upload: self.upload_progress,
            pending_uploads: !UploadState::pending().is_empty(),
            last_link: self.last_link.clone(),
            config: self.config.clone(),
        }
    }

    /// Avisa a la bandeja, a la interfaz y a D-Bus del estado actual.
    async fn publish(&mut self) {
        let snapshot = self.snapshot();
        let _ = self.status_tx.send(self.status);
        let _ = self.ui.try_send(UiEvent::Snapshot(snapshot.clone()));
        self.tray.update(move |t| t.snapshot = Some(snapshot)).await;
    }

    async fn set_status(&mut self, status: Status) {
        self.status = status;
        self.publish().await;
    }

    async fn run(mut self, mut rx: mpsc::UnboundedReceiver<Cmd>) {
        self.next_upload(); // reanuda las subidas que quedaron a medias
        while let Some(cmd) = rx.recv().await {
            if !self.handle(cmd).await {
                break;
            }
        }
        let _ = self.ui.send(UiEvent::Quit).await;
    }

    /// Devuelve `false` para salir.
    async fn handle(&mut self, cmd: Cmd) -> bool {
        let cmd = match (cmd, self.status) {
            (Cmd::Toggle, Status::Idle) => Cmd::Start,
            (Cmd::Toggle, Status::Countdown(_)) => Cmd::CancelCountdown,
            (Cmd::Toggle, Status::Recording | Status::Paused) => Cmd::Stop,
            (cmd, _) => cmd,
        };
        match cmd {
            Cmd::Start if self.status == Status::Idle => {
                self.set_status(Status::Starting).await;
                self.next_id += 1;
                let (id, tx) = (self.next_id, self.tx.clone());
                tokio::spawn(async move {
                    let _ = tx.send(Cmd::CaptureReady(id, Capture::open().await));
                });
            }
            Cmd::CaptureReady(id, result) if id == self.next_id && self.status == Status::Starting => match result {
                Ok(capture) => {
                    self.capture = Some((id, capture));
                    if self.config.countdown {
                        self.set_status(Status::Countdown(COUNTDOWN_SECONDS)).await;
                        self.after(Duration::from_secs(1), Cmd::Tick(id));
                    } else {
                        self.begin(id).await;
                    }
                }
                Err(e) => {
                    eprintln!("no se pudo iniciar: {e:#}");
                    notify("No se pudo iniciar la grabación", &format!("{e:#}"));
                    self.set_status(Status::Idle).await;
                }
            },
            Cmd::Tick(id) if id == self.next_id => {
                if let Status::Countdown(n) = self.status {
                    if n > 1 {
                        self.set_status(Status::Countdown(n - 1)).await;
                        self.after(Duration::from_secs(1), Cmd::Tick(id));
                    } else {
                        // Se oculta la cuenta y se espera a que desaparezca de la pantalla.
                        self.set_status(Status::Starting).await;
                        self.after(Duration::from_millis(250), Cmd::Begin(id));
                    }
                }
            }
            Cmd::Begin(id) if id == self.next_id && self.status == Status::Starting => self.begin(id).await,
            Cmd::CancelCountdown => {
                if let Status::Countdown(_) = self.status {
                    self.next_id += 1; // invalida los Tick pendientes
                    if let Some((_, capture)) = self.capture.take() {
                        capture.close().await;
                    }
                    self.set_status(Status::Idle).await;
                }
            }
            Cmd::TogglePause => match (&self.recording, self.status) {
                (Some((_, rec)), Status::Recording) => {
                    rec.pause();
                    self.recorded += self.since.take().map(|s| s.elapsed()).unwrap_or_default();
                    self.set_status(Status::Paused).await;
                }
                (Some((_, rec)), Status::Paused) => {
                    rec.resume();
                    self.since = Some(Instant::now());
                    self.set_status(Status::Recording).await;
                }
                _ => {}
            },
            Cmd::Stop | Cmd::Discard if matches!(self.status, Status::Recording | Status::Paused) => {
                self.discarding = matches!(cmd, Cmd::Discard);
                self.stop().await;
            }
            Cmd::Finished(id, result) if self.recording.as_ref().is_some_and(|(cur, _)| *cur == id) => {
                self.finished(result).await;
                if self.quitting {
                    return false;
                }
            }
            Cmd::UploadProgress(id, fraction) if self.upload.as_ref().is_some_and(|(cur, _)| *cur == id) => {
                let pct = (fraction * 100.0).floor() as u8;
                if self.upload_progress != Some(pct) {
                    self.upload_progress = Some(pct);
                    self.publish().await;
                }
            }
            Cmd::UploadDone(id, result) if self.upload.as_ref().is_some_and(|(cur, _)| *cur == id) => {
                self.upload = None;
                self.upload_progress = None;
                self.upload_done(&id, result);
                self.next_upload();
                self.publish().await;
            }
            Cmd::CancelUpload => {
                if let Some((_, cancel)) = &self.upload {
                    cancel.cancel();
                }
            }
            Cmd::RetryUploads => {
                self.failed.clear();
                self.next_upload();
                self.publish().await;
            }
            Cmd::CopyLastLink => {
                if let Some(link) = &self.last_link {
                    copy_to_clipboard(link);
                }
            }
            Cmd::OpenFolder => {
                let _ = std::fs::create_dir_all(&self.config.output_dir);
                open(&self.config.output_dir.display().to_string());
            }
            Cmd::OpenSettings => {
                let _ = self.ui.try_send(UiEvent::OpenSettings);
            }
            Cmd::Set(option, value) => {
                match option {
                    Option_::SystemAudio => self.config.record_system_audio = value,
                    Option_::Countdown => self.config.countdown = value,
                    Option_::OpenLink => self.config.open_link_after_upload = value,
                    Option_::ShowPanel => self.config.show_panel = value,
                }
                self.save_config().await;
            }
            Cmd::PanelPosition(x, y) => {
                self.config.panel_position = (x, y);
                if let Err(e) = self.config.save() {
                    eprintln!("no se pudo guardar la configuración: {e:#}");
                }
            }
            Cmd::ServerUrl(url) => {
                self.config.server_url = Some(url);
                self.save_config().await;
                self.failed.clear();
                self.next_upload();
            }
            Cmd::Quit => {
                if matches!(self.status, Status::Recording | Status::Paused | Status::Stopping) {
                    // Se espera a cerrar el MP4 para dejarlo en la cola de subidas.
                    self.quitting = true;
                    if self.status != Status::Stopping {
                        self.stop().await;
                    }
                } else {
                    if let Some((_, capture)) = self.capture.take() {
                        capture.close().await;
                    }
                    return false;
                }
            }
            _ => {}
        }
        true
    }

    fn after(&self, delay: Duration, cmd: Cmd) {
        let tx = self.tx.clone();
        tokio::spawn(async move {
            tokio::time::sleep(delay).await;
            let _ = tx.send(cmd);
        });
    }

    async fn save_config(&mut self) {
        if let Err(e) = self.config.save() {
            eprintln!("no se pudo guardar la configuración: {e:#}");
        }
        self.publish().await;
    }

    async fn begin(&mut self, id: u64) {
        let Some((_, capture)) = self.capture.take() else { return };
        let tx = self.tx.clone();
        let on_finish = move |result| {
            let _ = tx.send(Cmd::Finished(id, result));
        };
        match Recording::start(&self.config, capture, on_finish) {
            Ok(rec) => {
                println!("grabando en {}", rec.path.display());
                self.recording = Some((id, rec));
                self.recorded = Duration::ZERO;
                self.since = Some(Instant::now());
                self.set_status(Status::Recording).await;
            }
            Err(e) => {
                eprintln!("no se pudo iniciar: {e:#}");
                notify("No se pudo iniciar la grabación", &format!("{e:#}"));
                self.set_status(Status::Idle).await;
            }
        }
    }

    async fn stop(&mut self) {
        let Some((id, rec)) = &self.recording else { return };
        rec.stop(); // en pausa también: la sonda solo descarta buffers, el EOS pasa
        self.recorded += self.since.take().map(|s| s.elapsed()).unwrap_or_default();
        // Si el EOS nunca llega, no dejamos la app colgada.
        self.after(Duration::from_secs(15), Cmd::Finished(*id, Err(anyhow::anyhow!("timeout esperando el fin del archivo"))));
        self.set_status(Status::Stopping).await;
    }

    async fn finished(&mut self, result: Finished) {
        let (_, rec) = self.recording.take().expect("comprobado por el llamador");
        let path = rec.path.clone();
        rec.close().await;
        let discard = std::mem::take(&mut self.discarding);
        match result {
            _ if discard => {
                let _ = std::fs::remove_file(&path);
                println!("descartada: {}", path.display());
            }
            Ok(()) => {
                println!("guardado: {}", path.display());
                self.recorded_file(path);
            }
            Err(e) => {
                eprintln!("la grabación falló: {e:#}");
                // El MP4 puede haber quedado bien si el error llegó tras el EOS.
                if std::fs::metadata(&path).is_ok_and(|m| m.len() > 0) && !self.quitting {
                    notify("La grabación terminó con errores", &format!("{e:#}"));
                    self.recorded_file(path);
                } else {
                    notify("La grabación falló", &format!("{e:#}"));
                }
            }
        }
        self.recorded = Duration::ZERO;
        self.set_status(Status::Idle).await;
    }

    /// Pone en cola la subida del MP4 recién grabado (o avisa si no hay servidor).
    fn recorded_file(&mut self, path: PathBuf) {
        if !self.config.upload_configured() {
            notify_open(
                "Grabación guardada",
                &format!("{}\nConfigura el servidor en Ajustes… para subirla.", path.display()),
                path.display().to_string(),
            );
            return;
        }
        match UploadState::new(&path) {
            Ok(state) => {
                self.open_after.insert(state.id.clone());
                if !self.quitting {
                    notify("Subiendo al servidor", "Te aviso cuando el enlace esté listo.");
                    self.next_upload();
                }
            }
            Err(e) => notify("No se pudo preparar la subida", &format!("{e:#}")),
        }
    }

    /// Lanza la siguiente subida pendiente si no hay otra en curso.
    fn next_upload(&mut self) {
        if self.upload.is_some() || self.quitting {
            return;
        }
        let Some(state) = UploadState::pending().into_iter().find(|s| !self.failed.contains(&s.id)) else { return };
        let uploader = match api::Client::from_config(&self.config) {
            Ok(client) => Uploader::new(client),
            Err(_) => return, // sin configurar: quedan en cola hasta que haya URL y token
        };
        let (id, cancel, tx) = (state.id.clone(), CancellationToken::new(), self.tx.clone());
        self.upload = Some((id.clone(), cancel.clone()));
        self.upload_progress = Some(0);
        tokio::spawn(async move {
            let (tx2, id2) = (tx.clone(), id.clone());
            let result = uploader
                .process(state, cancel, move |f| {
                    let _ = tx2.send(Cmd::UploadProgress(id2.clone(), f));
                })
                .await;
            let _ = tx.send(Cmd::UploadDone(id, result));
        });
    }

    fn upload_done(&mut self, id: &str, result: Result<String, UploadError>) {
        match result {
            Ok(link) => {
                println!("subido: {link}");
                copy_to_clipboard(&link);
                self.last_link = Some(link.clone());
                if self.open_after.remove(id) && self.config.open_link_after_upload {
                    open(&link);
                    notify("Video listo", &format!("{link}\nEnlace copiado al portapapeles."));
                } else {
                    notify_open("Video listo", &format!("{link}\nEnlace copiado al portapapeles."), link.clone());
                }
            }
            Err(UploadError::Cancelled) => println!("subida cancelada"),
            Err(e) => {
                eprintln!("la subida falló: {e}");
                self.failed.insert(id.to_owned());
                notify("La subida falló", &format!("{e}\nReinténtala desde el menú de la bandeja."));
            }
        }
    }
}

pub fn copy_to_clipboard(text: &str) {
    if let Err(e) = std::process::Command::new("wl-copy").arg(text).spawn() {
        eprintln!("no se pudo copiar al portapapeles (¿falta wl-clipboard?): {e}");
    }
}

pub fn open(target: &str) {
    let _ = std::process::Command::new("xdg-open").arg(target).spawn();
}

fn notify(summary: &str, body: &str) {
    show_notification(summary, body, None);
}

/// Notificación que, al pulsarla, abre `target` (URL o archivo).
fn notify_open(summary: &str, body: &str, target: String) {
    show_notification(summary, body, Some(target));
}

fn show_notification(summary: &str, body: &str, target: Option<String>) {
    let (summary, body) = (summary.to_owned(), body.to_owned());
    std::thread::spawn(move || {
        let mut n = notify_rust::Notification::new();
        n.appname("Mis Looms").summary(&summary).body(&body).icon("media-record");
        if target.is_some() {
            n.action("default", "Abrir");
        }
        match n.show() {
            Ok(handle) => {
                if let Some(target) = target {
                    handle.wait_for_action(|action| {
                        if action == "default" {
                            open(&target);
                        }
                    });
                }
            }
            Err(e) => eprintln!("no se pudo mostrar la notificación: {e}"),
        }
    });
}
