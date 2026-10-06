use std::path::PathBuf;

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

/// Configuración del usuario en `~/.config/mis-looms/config.json`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    pub output_dir: PathBuf,
    pub record_mic: bool,
    pub record_system_audio: bool,
    pub framerate: u32,
    /// Altura máxima del video (0 = resolución nativa).
    pub max_height: u32,
    pub video_bitrate_kbps: u32,
}

impl Default for Config {
    fn default() -> Self {
        let videos = dirs::video_dir()
            .or_else(|| dirs::home_dir().map(|h| h.join("Videos")))
            .unwrap_or_else(|| PathBuf::from("."));
        Self {
            output_dir: videos.join("mis-looms"),
            record_mic: true,
            record_system_audio: true,
            framerate: 30,
            max_height: 1080,
            video_bitrate_kbps: 8000,
        }
    }
}

fn config_dir() -> PathBuf {
    dirs::config_dir().unwrap_or_else(|| PathBuf::from(".")).join("mis-looms")
}

fn state_dir() -> PathBuf {
    dirs::state_dir()
        .or_else(dirs::data_local_dir)
        .unwrap_or_else(|| PathBuf::from("."))
        .join("mis-looms")
}

impl Config {
    /// Carga la configuración; si no existe, escribe la de por defecto.
    pub fn load() -> Result<Self> {
        let path = config_dir().join("config.json");
        if path.exists() {
            let raw = std::fs::read_to_string(&path)?;
            return serde_json::from_str(&raw).with_context(|| format!("config inválida: {}", path.display()));
        }
        let config = Self::default();
        std::fs::create_dir_all(config_dir())?;
        std::fs::write(&path, serde_json::to_string_pretty(&config)?)?;
        Ok(config)
    }
}

/// Token del portal ScreenCast para no tener que elegir pantalla en cada grabación.
pub fn load_restore_token() -> Option<String> {
    std::fs::read_to_string(state_dir().join("restore_token"))
        .ok()
        .map(|t| t.trim().to_owned())
        .filter(|t| !t.is_empty())
}

pub fn save_restore_token(token: Option<&str>) {
    let path = state_dir().join("restore_token");
    let result = match token {
        Some(t) => std::fs::create_dir_all(state_dir()).and_then(|_| std::fs::write(&path, t)),
        None => std::fs::remove_file(&path).or(Ok(())),
    };
    if let Err(e) = result {
        eprintln!("no se pudo guardar el restore token: {e}");
    }
}
