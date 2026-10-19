use ksni::menu::{CheckmarkItem, StandardItem};
use tokio::sync::mpsc;

use crate::{Cmd, Option_, Snapshot, Status};

/// Icono en la bandeja (StatusNotifierItem, lo muestra Waybar/quickshell).
pub struct Tray {
    pub snapshot: Option<Snapshot>,
    tx: mpsc::UnboundedSender<Cmd>,
}

impl Tray {
    pub fn new(tx: mpsc::UnboundedSender<Cmd>) -> Self {
        Self { snapshot: None, tx }
    }

    fn status(&self) -> Status {
        self.snapshot.as_ref().map_or(Status::Idle, |s| s.status)
    }
}

fn item(label: impl Into<String>, cmd: fn() -> Cmd) -> ksni::MenuItem<Tray> {
    StandardItem {
        label: label.into(),
        activate: Box::new(move |t: &mut Tray| {
            let _ = t.tx.send(cmd());
        }),
        ..Default::default()
    }
    .into()
}

fn disabled(label: impl Into<String>) -> ksni::MenuItem<Tray> {
    StandardItem { label: label.into(), enabled: false, ..Default::default() }.into()
}

fn check(label: &str, checked: bool, option: Option_) -> ksni::MenuItem<Tray> {
    CheckmarkItem {
        label: label.into(),
        checked,
        activate: Box::new(move |t: &mut Tray| {
            let _ = t.tx.send(Cmd::Set(option, !checked));
        }),
        ..Default::default()
    }
    .into()
}

impl ksni::Tray for Tray {
    fn id(&self) -> String {
        "mis-looms".into()
    }

    fn title(&self) -> String {
        match self.status() {
            Status::Idle => match self.snapshot.as_ref().and_then(|s| s.upload) {
                Some(p) => format!("Mis Looms — subiendo {p} %"),
                None => "Mis Looms".into(),
            },
            Status::Starting => "Mis Looms — eligiendo pantalla…".into(),
            Status::Countdown(n) => format!("Mis Looms — empieza en {n}"),
            Status::Recording => "Mis Looms — grabando".into(),
            Status::Paused => "Mis Looms — en pausa".into(),
            Status::Stopping => "Mis Looms — finalizando…".into(),
        }
    }

    fn icon_name(&self) -> String {
        match self.status() {
            Status::Recording => "media-playback-stop",
            Status::Paused => "media-playback-pause",
            Status::Starting | Status::Countdown(_) | Status::Stopping => "content-loading-symbolic",
            Status::Idle => "media-record",
        }
        .into()
    }

    fn status(&self) -> ksni::Status {
        if self.status() == Status::Recording { ksni::Status::NeedsAttention } else { ksni::Status::Active }
    }

    // Clic izquierdo: iniciar/finalizar.
    fn activate(&mut self, _x: i32, _y: i32) {
        let _ = self.tx.send(Cmd::Toggle);
    }

    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        let Some(s) = &self.snapshot else { return vec![] };
        let mut menu = match s.status {
            Status::Idle => vec![item("Iniciar grabación", || Cmd::Start)],
            Status::Starting => vec![disabled("Eligiendo pantalla…")],
            Status::Countdown(n) => vec![item(format!("Cancelar (empieza en {n})"), || Cmd::CancelCountdown)],
            Status::Recording | Status::Paused => vec![
                item("Finalizar grabación", || Cmd::Stop),
                item(if s.status == Status::Paused { "Reanudar grabación" } else { "Pausar grabación" }, || {
                    Cmd::TogglePause
                }),
                item("Descartar grabación", || Cmd::Discard),
            ],
            Status::Stopping => vec![disabled("Finalizando…")],
        };
        menu.push(ksni::MenuItem::Separator);
        if let Some(p) = s.upload {
            menu.push(disabled(format!("Subiendo al servidor… {p} %")));
            menu.push(item("Cancelar subida", || Cmd::CancelUpload));
        } else if s.pending_uploads {
            menu.push(item("Reintentar subidas pendientes", || Cmd::RetryUploads));
        }
        if s.last_link.is_some() {
            menu.push(item("Copiar último enlace", || Cmd::CopyLastLink));
        }
        if s.upload.is_some() || s.pending_uploads || s.last_link.is_some() {
            menu.push(ksni::MenuItem::Separator);
        }
        menu.extend([
            check("Grabar audio del sistema", s.config.record_system_audio, Option_::SystemAudio),
            check(&format!("Cuenta regresiva de {} s", crate::COUNTDOWN_SECONDS), s.config.countdown, Option_::Countdown),
            check("Abrir el enlace al terminar", s.config.open_link_after_upload, Option_::OpenLink),
            check("Mostrar controles flotantes", s.config.show_panel, Option_::ShowPanel),
            ksni::MenuItem::Separator,
            item("Abrir carpeta de grabaciones", || Cmd::OpenFolder),
            item("Ajustes…", || Cmd::OpenSettings),
            ksni::MenuItem::Separator,
            item("Salir de Mis Looms", || Cmd::Quit),
        ]);
        menu
    }
}
