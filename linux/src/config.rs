use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use anyhow::{Context, Result, anyhow, bail};
use serde::{Deserialize, Serialize};

/// Configuración del usuario en `~/.config/mis-looms/config.json`.
/// El token de la API no va aquí: se guarda en el llavero (Secret Service).
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
    /// Base del servidor, p. ej. `https://jmarreros.com/mis-looms` (sin `/api`).
    pub server_url: Option<String>,
    /// Cuenta regresiva de 3 s antes de empezar a grabar.
    pub countdown: bool,
    /// Abrir en el navegador el enlace de las grabaciones de la sesión al terminar de subir.
    pub open_link_after_upload: bool,
    /// Mostrar la píldora de controles flotantes.
    pub show_panel: bool,
    /// Posición de la píldora: márgenes izquierdo e inferior en píxeles lógicos.
    pub panel_position: (i32, i32),
}

impl Default for Config {
    fn default() -> Self {
        let videos = dirs::video_dir()
            .or_else(|| dirs::home_dir().map(|h| h.join("Videos")))
            .unwrap_or_else(|| PathBuf::from("."));
        Self {
            output_dir: videos.join("mis-looms"),
            record_mic: true,
            record_system_audio: false,
            framerate: 30,
            max_height: 1080,
            video_bitrate_kbps: 8000,
            server_url: None,
            countdown: true,
            open_link_after_upload: true,
            show_panel: true,
            panel_position: (24, 24),
        }
    }
}

fn config_dir() -> PathBuf {
    dirs::config_dir().unwrap_or_else(|| PathBuf::from(".")).join("mis-looms")
}

pub fn state_dir() -> PathBuf {
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
        config.save()?;
        Ok(config)
    }

    pub fn save(&self) -> Result<()> {
        std::fs::create_dir_all(config_dir())?;
        let path = config_dir().join("config.json");
        let tmp = path.with_extension("json.tmp");
        std::fs::write(&tmp, serde_json::to_string_pretty(self)?)?;
        std::fs::rename(tmp, path)?;
        Ok(())
    }

    /// URL del servidor; `MISLOOMS_URL` tiene prioridad (scripts y pruebas).
    pub fn server_url(&self) -> Option<String> {
        if let Ok(v) = std::env::var("MISLOOMS_URL") {
            return normalize_url(&v);
        }
        self.server_url.clone()
    }

    /// `true` si hay URL y token: las grabaciones se suben solas.
    pub fn upload_configured(&self) -> bool {
        self.server_url().is_some() && api_token().is_some()
    }
}

/// Acepta "midominio.com", "https://midominio.com/" o "…/api" y devuelve la base sin barra final.
pub fn normalize_url(text: &str) -> Option<String> {
    let mut t = text.trim().to_owned();
    if t.is_empty() {
        return None;
    }
    if !t.contains("://") {
        t = format!("https://{t}");
    }
    while t.ends_with('/') {
        t.pop();
    }
    if let Some(base) = t.strip_suffix("/api") {
        t = base.to_owned();
    }
    let url = reqwest::Url::parse(&t).ok()?;
    (url.host().is_some() && matches!(url.scheme(), "http" | "https")).then_some(t)
}

// MARK: - Token en el llavero (Secret Service vía `secret-tool`, de libsecret)

const SECRET_ATTRS: [&str; 4] = ["service", "org.mislooms.Recorder", "account", "token-api"];

/// Token de la API; `MISLOOMS_TOKEN` tiene prioridad y entonces no se toca el llavero.
pub fn api_token() -> Option<String> {
    if let Ok(v) = std::env::var("MISLOOMS_TOKEN")
        && !v.is_empty() {
            return Some(v);
        }
    let out = Command::new("secret-tool").arg("lookup").args(SECRET_ATTRS).output().ok()?;
    let token = String::from_utf8(out.stdout).ok()?.trim().to_owned();
    (out.status.success() && !token.is_empty()).then_some(token)
}

pub fn save_api_token(token: &str) -> Result<()> {
    let mut child = Command::new("secret-tool")
        .args(["store", "--label=Mis Looms (token de la API)"])
        .args(SECRET_ATTRS)
        .stdin(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("falta `secret-tool` (paquete libsecret)")?;
    child.stdin.take().expect("stdin con pipe").write_all(token.as_bytes())?;
    let out = child.wait_with_output()?;
    if !out.status.success() {
        bail!("no se pudo guardar el token en el llavero: {}", String::from_utf8_lossy(&out.stderr).trim());
    }
    match api_token() {
        Some(t) if t == token => Ok(()),
        _ => Err(anyhow!("el llavero no devolvió el token recién guardado")),
    }
}

// MARK: - Restore token del portal

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
