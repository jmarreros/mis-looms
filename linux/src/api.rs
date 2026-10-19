use std::time::Duration;

use reqwest::{Method, StatusCode};
use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

use crate::config::{self, Config};

/// Errores de la API de Mis Looms, con mensajes listos para mostrar.
#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error("Falta configurar la URL del servidor y el token (menú › Ajustes…).")]
    NotConfigured,
    #[error("El servidor rechazó el token. Genera uno nuevo en el panel › Token de la app.")]
    InvalidToken,
    /// 409: la subida ya no está en curso (completada, abortada o caducada).
    #[error("El servidor ya no tiene abierta esta subida.")]
    UploadClosed,
    #[error("El servidor respondió {0}: {1}")]
    Server(u16, String),
    #[error("El servidor devolvió una respuesta inesperada.")]
    InvalidResponse,
    #[error("No se pudo conectar con el servidor: {0}")]
    Network(#[from] reqwest::Error),
}

#[derive(Debug, Clone, Deserialize)]
pub struct RemoteVideo {
    pub slug: String,
    pub share_url: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SignedPart {
    pub part_number: u32,
    pub url: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct UploadedPart {
    pub part_number: u32,
    pub etag: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Metadata {
    pub duration: Option<f64>,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

#[derive(Debug, Deserialize)]
pub struct StartedUpload {
    pub video: RemoteVideo,
    #[allow(dead_code)]
    pub upload_id: String,
    pub part_size: u64,
    pub parts: Vec<SignedPart>,
}

#[derive(Debug, Deserialize)]
pub struct ThumbnailTarget {
    pub upload_url: String,
    pub headers: std::collections::HashMap<String, String>,
}

/// Cliente de docs/api.md. Solo habla con Laravel; las partes y la miniatura
/// se suben directo a S3 desde `uploader`.
#[derive(Clone)]
pub struct Client {
    base: String,
    token: String,
    http: reqwest::Client,
}

impl Client {
    pub fn from_config(config: &Config) -> Result<Self, ApiError> {
        match (config.server_url(), config::api_token()) {
            (Some(url), Some(token)) => Self::new(&url, &token),
            _ => Err(ApiError::NotConfigured),
        }
    }

    pub fn new(url: &str, token: &str) -> Result<Self, ApiError> {
        let base = config::normalize_url(url).ok_or(ApiError::NotConfigured)?;
        if token.trim().is_empty() {
            return Err(ApiError::NotConfigured);
        }
        let http = reqwest::Client::builder()
            .timeout(Duration::from_secs(30))
            .user_agent(concat!("mis-looms-linux/", env!("CARGO_PKG_VERSION")))
            .build()?;
        Ok(Self { base: format!("{base}/api"), token: token.trim().to_owned(), http })
    }

    pub async fn ping(&self) -> Result<(), ApiError> {
        self.send(Method::GET, "ping", None).await.map(drop)
    }

    pub async fn create(&self, size: u64, meta: &Metadata) -> Result<StartedUpload, ApiError> {
        let mut body = meta_fields(meta);
        body["size"] = json!(size);
        self.request(Method::POST, "videos", Some(body)).await
    }

    pub async fn sign(&self, slug: &str, parts: &[u32]) -> Result<Vec<SignedPart>, ApiError> {
        #[derive(Deserialize)]
        struct Response {
            parts: Vec<SignedPart>,
        }
        let r: Response = self.request(Method::POST, &format!("videos/{slug}/parts"), Some(json!({ "parts": parts }))).await?;
        Ok(r.parts)
    }

    pub async fn thumbnail_target(&self, slug: &str) -> Result<ThumbnailTarget, ApiError> {
        self.request(Method::POST, &format!("videos/{slug}/thumbnail"), Some(json!({}))).await
    }

    pub async fn complete(
        &self,
        slug: &str,
        parts: &[UploadedPart],
        meta: &Metadata,
        has_thumbnail: bool,
    ) -> Result<RemoteVideo, ApiError> {
        #[derive(Deserialize)]
        struct Response {
            video: RemoteVideo,
        }
        let mut sorted = parts.to_vec();
        sorted.sort_by_key(|p| p.part_number);
        let mut body = meta_fields(meta);
        body["parts"] = json!(sorted);
        body["has_thumbnail"] = json!(has_thumbnail);
        let r: Response = self.request(Method::POST, &format!("videos/{slug}/complete"), Some(body)).await?;
        Ok(r.video)
    }

    pub async fn abort(&self, slug: &str) -> Result<(), ApiError> {
        self.send(Method::POST, &format!("videos/{slug}/abort"), Some(json!({}))).await.map(drop)
    }

    // MARK: - Internos

    async fn request<T: DeserializeOwned>(&self, method: Method, path: &str, body: Option<Value>) -> Result<T, ApiError> {
        let data = self.send(method, path, body).await?;
        serde_json::from_slice(&data).map_err(|_| ApiError::InvalidResponse)
    }

    async fn send(&self, method: Method, path: &str, body: Option<Value>) -> Result<Vec<u8>, ApiError> {
        let mut req = self
            .http
            .request(method, format!("{}/{path}", self.base))
            .bearer_auth(&self.token)
            .header("Accept", "application/json");
        if let Some(body) = body {
            req = req.json(&body);
        }
        let res = req.send().await?;
        let status = res.status();
        let data = res.bytes().await?.to_vec();
        match status {
            s if s.is_success() => Ok(data),
            StatusCode::UNAUTHORIZED => Err(ApiError::InvalidToken),
            StatusCode::CONFLICT => Err(ApiError::UploadClosed),
            s => {
                let message = serde_json::from_slice::<Value>(&data)
                    .ok()
                    .and_then(|v| v.get("message")?.as_str().map(str::to_owned))
                    .unwrap_or_else(|| s.canonical_reason().unwrap_or("error").to_owned());
                Err(ApiError::Server(s.as_u16(), message))
            }
        }
    }
}

fn meta_fields(meta: &Metadata) -> Value {
    let mut v = json!({});
    if let Some(d) = meta.duration {
        v["duration"] = json!(d);
    }
    if let Some(w) = meta.width {
        v["width"] = json!(w);
    }
    if let Some(h) = meta.height {
        v["height"] = json!(h);
    }
    v
}
