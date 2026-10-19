use std::io::Write;
use std::path::PathBuf;

use anyhow::{Result, bail};
use gstreamer as gst;
use tokio_util::sync::CancellationToken;

use crate::api::Client;
use crate::config::Config;
use crate::uploader::{UploadState, Uploader};

/// `mis-looms subir video.mp4`: sube un archivo sin interfaz (scripts y pruebas).
/// Ctrl+C cancela y aborta la subida en el servidor.
pub fn upload(file: Option<PathBuf>) -> Result<()> {
    let Some(file) = file else { bail!("uso: mis-looms subir ARCHIVO.mp4") };
    gst::init()?;
    let state = UploadState::new(&file.canonicalize()?)?;
    tokio::runtime::Runtime::new()?.block_on(run(vec![state]))
}

/// `mis-looms reanudar`: reanuda las subidas pendientes.
pub fn resume() -> Result<()> {
    gst::init()?;
    let pending = UploadState::pending();
    if pending.is_empty() {
        println!("no hay subidas pendientes");
        return Ok(());
    }
    tokio::runtime::Runtime::new()?.block_on(run(pending))
}

async fn run(states: Vec<UploadState>) -> Result<()> {
    let uploader = Uploader::new(Client::from_config(&Config::load()?)?);
    let cancel = CancellationToken::new();
    {
        let cancel = cancel.clone();
        tokio::spawn(async move {
            let _ = tokio::signal::ctrl_c().await;
            eprintln!("\ncancelando…");
            cancel.cancel();
        });
    }
    let mut failed = false;
    for state in states {
        println!("subiendo {}", state.file.display());
        let result = uploader
            .process(state, cancel.clone(), |f| {
                print!("\r{:5.1} %", f * 100.0);
                let _ = std::io::stdout().flush();
            })
            .await;
        println!();
        match result {
            Ok(link) => println!("{link}"),
            Err(e) => {
                eprintln!("error: {e}");
                failed = true;
            }
        }
        if cancel.is_cancelled() {
            break;
        }
    }
    if failed {
        std::process::exit(1);
    }
    Ok(())
}
