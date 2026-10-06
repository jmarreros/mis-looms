use ksni::menu::StandardItem;
use tokio::sync::mpsc;

use crate::{Cmd, Status};

/// Icono en la bandeja (StatusNotifierItem, lo muestra Waybar).
pub struct Tray {
    pub status: Status,
    pub tx: mpsc::UnboundedSender<Cmd>,
}

impl ksni::Tray for Tray {
    fn id(&self) -> String {
        "mis-looms".into()
    }

    fn title(&self) -> String {
        match self.status {
            Status::Idle => "Mis Looms",
            Status::Starting => "Mis Looms — eligiendo pantalla…",
            Status::Recording => "Mis Looms — grabando",
            Status::Stopping => "Mis Looms — guardando…",
        }
        .into()
    }

    fn icon_name(&self) -> String {
        match self.status {
            Status::Recording => "media-playback-stop",
            Status::Starting | Status::Stopping => "content-loading-symbolic",
            Status::Idle => "media-record",
        }
        .into()
    }

    fn status(&self) -> ksni::Status {
        if self.status == Status::Recording { ksni::Status::NeedsAttention } else { ksni::Status::Active }
    }

    // Clic izquierdo: iniciar/detener.
    fn activate(&mut self, _x: i32, _y: i32) {
        let _ = self.tx.send(Cmd::Toggle);
    }

    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        let (label, enabled) = match self.status {
            Status::Idle => ("Grabar pantalla", true),
            Status::Recording => ("Detener grabación", true),
            Status::Starting => ("Iniciando…", false),
            Status::Stopping => ("Guardando…", false),
        };
        vec![
            StandardItem {
                label: label.into(),
                enabled,
                activate: Box::new(|t: &mut Self| {
                    let _ = t.tx.send(Cmd::Toggle);
                }),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Abrir carpeta de videos".into(),
                activate: Box::new(|t: &mut Self| {
                    let _ = t.tx.send(Cmd::OpenFolder);
                }),
                ..Default::default()
            }
            .into(),
            ksni::MenuItem::Separator,
            StandardItem {
                label: "Salir".into(),
                icon_name: "application-exit".into(),
                activate: Box::new(|t: &mut Self| {
                    let _ = t.tx.send(Cmd::Quit);
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}
