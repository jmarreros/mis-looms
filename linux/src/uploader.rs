use std::collections::{HashMap, HashSet};
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Result, anyhow};
use futures_util::StreamExt;
use futures_util::stream::FuturesUnordered;
use serde::{Deserialize, Serialize};
use tokio_util::sync::CancellationToken;

use crate::api::{ApiError, Client, Metadata, UploadedPart};
use crate::{config, media};

pub const PARALLEL_PARTS: usize = 3;
pub const ATTEMPTS_PER_PART: u32 = 4;

#[derive(Debug, thiserror::Error)]
pub enum UploadError {
    #[error("Ya no existe el archivo {0}.")]
    MissingFile(String),
    #[error("S3 rechazó la parte {part} (HTTP {status}).")]
    S3 { status: u16, part: u32 },
    #[error("Subida cancelada.")]
    Cancelled,
    #[error(transparent)]
    Api(#[from] ApiError),
    #[error("{0:#}")]
    Other(#[from] anyhow::Error),
}

/// Subida pendiente, guardada en disco para poder reanudarla si la app se cierra o falla.
/// `slug == None` significa que el servidor todavía no ha creado el video.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UploadState {
    pub id: String,
    pub file: PathBuf,
    pub slug: Option<String>,
    pub size: u64,
    #[serde(default)]
    pub part_size: u64,
    #[serde(default)]
    pub total_parts: u32,
    #[serde(default)]
    pub meta: Metadata,
    /// Las partes que ya están en S3, con su ETag.
    #[serde(default)]
    pub parts: Vec<UploadedPart>,
}

impl UploadState {
    pub fn dir() -> PathBuf {
        match std::env::var_os("MISLOOMS_ESTADO") {
            Some(p) => PathBuf::from(p),
            None => config::state_dir().join("subidas"),
        }
    }

    pub fn new(file: &Path) -> Result<Self> {
        let size = std::fs::metadata(file)?.len();
        // El id empieza por la fecha para que `pending()` las devuelva en orden.
        let id = format!("{}-{:08x}", chrono::Local::now().format("%Y%m%d%H%M%S"), rand_u32());
        let state = Self {
            id,
            file: file.to_owned(),
            slug: None,
            size,
            part_size: 0,
            total_parts: 0,
            meta: Metadata::default(),
            parts: vec![],
        };
        state.save();
        Ok(state)
    }

    pub fn pending() -> Vec<Self> {
        let Ok(entries) = std::fs::read_dir(Self::dir()) else { return vec![] };
        let mut files: Vec<_> = entries
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.extension().is_some_and(|x| x == "json"))
            .collect();
        files.sort();
        files
            .iter()
            .filter_map(|p| serde_json::from_slice(&std::fs::read(p).ok()?).ok())
            .collect()
    }

    pub fn load(id: &str) -> Option<Self> {
        serde_json::from_slice(&std::fs::read(Self::dir().join(format!("{id}.json"))).ok()?).ok()
    }

    fn path(&self) -> PathBuf {
        Self::dir().join(format!("{}.json", self.id))
    }

    pub fn save(&self) {
        let result = std::fs::create_dir_all(Self::dir()).and_then(|_| {
            let tmp = self.path().with_extension("tmp");
            std::fs::write(&tmp, serde_json::to_vec_pretty(self).expect("serializable"))?;
            std::fs::rename(tmp, self.path())
        });
        if let Err(e) = result {
            eprintln!("no se pudo guardar el estado de la subida: {e}");
        }
    }

    pub fn delete(&self) {
        let _ = std::fs::remove_file(self.path());
    }

    fn missing_parts(&self) -> Vec<u32> {
        let done: HashSet<u32> = self.parts.iter().map(|p| p.part_number).collect();
        (1..=self.total_parts).filter(|n| !done.contains(n)).collect()
    }

    /// Todas las partes miden `part_size`, salvo la última, que lleva el resto.
    fn part_len(&self, number: u32) -> u64 {
        self.part_size.min(self.size - (number as u64 - 1) * self.part_size)
    }
}

fn rand_u32() -> u32 {
    use std::hash::{BuildHasher, RandomState};
    RandomState::new().hash_one(std::time::SystemTime::now()) as u32
}

/// Suma los bytes ya subidos y los que van en vuelo para dar un progreso global.
struct Meter {
    inner: Mutex<(u64, HashMap<u32, u64>)>,
    total: u64,
    on_change: Box<dyn Fn(f64) + Send + Sync>,
}

impl Meter {
    fn update(&self, change: impl FnOnce(&mut (u64, HashMap<u32, u64>))) {
        let fraction = {
            let mut inner = self.inner.lock().unwrap();
            change(&mut inner);
            let sent = inner.0 + inner.1.values().sum::<u64>();
            (sent as f64 / self.total.max(1) as f64).min(1.0)
        };
        (self.on_change)(fraction);
    }
    fn progress(&self, part: u32, sent: u64) {
        self.update(|i| {
            i.1.insert(part, sent);
        });
    }
    fn reset(&self, part: u32) {
        self.update(|i| {
            i.1.remove(&part);
        });
    }
    fn done(&self, part: u32, bytes: u64) {
        self.update(|i| {
            i.1.remove(&part);
            i.0 += bytes;
        });
    }
}

/// Sube un MP4 a S3 con multipart prefirmado por Laravel: partes en paralelo, reintentos por
/// parte, miniatura y cierre. El estado se guarda tras cada parte para poder reanudar.
#[derive(Clone)]
pub struct Uploader {
    api: Client,
    s3: reqwest::Client,
}

impl Uploader {
    pub fn new(api: Client) -> Self {
        let s3 = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(20))
            .timeout(Duration::from_secs(600))
            .build()
            .expect("cliente HTTP");
        Self { api, s3 }
    }

    /// Ejecuta (o reanuda) una subida y devuelve el enlace para compartir.
    /// Si se cancela, aborta la subida en el servidor y olvida el estado.
    pub async fn process(
        &self,
        state: UploadState,
        cancel: CancellationToken,
        progress: impl Fn(f64) + Send + Sync + 'static,
    ) -> Result<String, UploadError> {
        let id = state.id.clone();
        tokio::select! {
            r = self.run(state, Box::new(progress)) => r,
            _ = cancel.cancelled() => {
                // El estado en disco tiene el slug si el servidor ya creó el video.
                if let Some(state) = UploadState::load(&id) {
                    state.delete();
                    if let Some(slug) = &state.slug {
                        let _ = self.api.abort(slug).await;
                    }
                }
                Err(UploadError::Cancelled)
            }
        }
    }

    async fn run(&self, mut state: UploadState, progress: Box<dyn Fn(f64) + Send + Sync>) -> Result<String, UploadError> {
        if !state.file.exists() {
            state.delete();
            let name = state.file.file_name().unwrap_or_default().to_string_lossy().into_owned();
            return Err(UploadError::MissingFile(name));
        }

        // 1. Crear el video en el servidor, o recuperar las URLs de las partes que faltan.
        let mut signed: HashMap<u32, String> = HashMap::new();
        if let Some(slug) = state.slug.clone() {
            let missing = state.missing_parts();
            if !missing.is_empty() {
                match self.api.sign(&slug, &missing).await {
                    Ok(parts) => signed = parts.into_iter().map(|p| (p.part_number, p.url)).collect(),
                    Err(ApiError::UploadClosed) => {
                        // Caducó o se canceló en el servidor: empezar de cero con el mismo archivo.
                        state.slug = None;
                        state.parts.clear();
                    }
                    Err(e) => return Err(e.into()),
                }
            }
        }
        if state.slug.is_none() {
            let file = state.file.clone();
            state.meta = tokio::task::spawn_blocking(move || media::metadata(&file)).await.unwrap_or_default();
            let started = self.api.create(state.size, &state.meta).await?;
            state.slug = Some(started.video.slug);
            state.part_size = started.part_size;
            state.total_parts = started.parts.len() as u32;
            signed = started.parts.into_iter().map(|p| (p.part_number, p.url)).collect();
        }
        state.save();
        let slug = state.slug.clone().ok_or(ApiError::InvalidResponse)?;

        // 2. Subir las partes que faltan, de 3 en 3.
        let already: u64 = state.parts.iter().map(|p| state.part_len(p.part_number)).sum();
        let meter = Arc::new(Meter { inner: Mutex::new((already, HashMap::new())), total: state.size, on_change: progress });
        meter.done(0, 0); // publica el progreso inicial (0 % o lo ya subido)
        let mut queue = state.missing_parts().into_iter();
        let mut running = FuturesUnordered::new();
        let launch = |n: u32, running: &mut FuturesUnordered<_>, state: &UploadState| {
            let (this, meter, url) = (self.clone(), meter.clone(), signed.get(&n).cloned());
            let (file, len, offset, slug) = (state.file.clone(), state.part_len(n), (n as u64 - 1) * state.part_size, slug.clone());
            running.push(async move { this.upload_part(n, &slug, &file, offset, len, url, &meter).await });
        };
        for n in queue.by_ref().take(PARALLEL_PARTS) {
            launch(n, &mut running, &state);
        }
        while let Some(result) = running.next().await {
            state.parts.push(result?);
            state.save();
            if let Some(n) = queue.next() {
                launch(n, &mut running, &state);
            }
        }

        // 3. Miniatura (si falla, el video se publica igualmente sin ella).
        let has_thumbnail = match self.upload_thumbnail(&state, &slug).await {
            Ok(()) => true,
            Err(e) => {
                eprintln!("sin miniatura: {e:#}");
                false
            }
        };

        // 4. Cerrar la subida.
        match self.api.complete(&slug, &state.parts, &state.meta, has_thumbnail).await {
            Ok(video) => {
                state.delete();
                Ok(video.share_url)
            }
            Err(ApiError::UploadClosed) => {
                state.delete(); // ya no se puede continuar; reintentar solo duplicaría el video
                Err(ApiError::UploadClosed.into())
            }
            Err(e) => Err(e.into()),
        }
    }

    // MARK: - Partes

    #[allow(clippy::too_many_arguments)]
    async fn upload_part(
        &self,
        number: u32,
        slug: &str,
        file: &Path,
        offset: u64,
        len: u64,
        url: Option<String>,
        meter: &Arc<Meter>,
    ) -> Result<UploadedPart, UploadError> {
        let data = {
            let file = file.to_owned();
            tokio::task::spawn_blocking(move || read_range(&file, offset, len))
                .await
                .map_err(|e| anyhow!(e))??
        };
        let mut url = url;
        let mut attempt = 0;
        loop {
            let result = async {
                if url.is_none() {
                    url = self.api.sign(slug, &[number]).await?.into_iter().next().map(|p| p.url);
                }
                let target = url.clone().ok_or(ApiError::InvalidResponse)?;
                let m = meter.clone();
                self.put(&target, data.clone(), number, &[], move |sent| m.progress(number, sent)).await
            }
            .await;
            match result {
                Ok(etag) => {
                    meter.done(number, len);
                    return Ok(UploadedPart { part_number: number, etag });
                }
                Err(e) => {
                    meter.reset(number);
                    attempt += 1;
                    if matches!(e, UploadError::Api(_)) || attempt >= ATTEMPTS_PER_PART {
                        return Err(e);
                    }
                    // 403: la URL prefirmada caducó. Cualquier otro fallo: reintento con espera creciente.
                    if matches!(e, UploadError::S3 { status: 403, .. }) {
                        url = None;
                    }
                    eprintln!("parte {number}: {e}; reintento {attempt}");
                    tokio::time::sleep(Duration::from_secs(1 << (attempt - 1))).await;
                }
            }
        }
    }

    async fn put(
        &self,
        url: &str,
        data: Vec<u8>,
        part: u32,
        headers: &[(String, String)],
        on_sent: impl Fn(u64) + Send + Sync + 'static,
    ) -> Result<String, UploadError> {
        let len = data.len();
        // El cuerpo va en trozos de 64 KB para poder informar del progreso.
        let chunks: Vec<bytes::Bytes> = bytes::Bytes::from(data).chunks(64 * 1024).map(bytes::Bytes::copy_from_slice).collect();
        let mut sent = 0u64;
        let stream = futures_util::stream::iter(chunks).map(move |chunk| {
            sent += chunk.len() as u64;
            on_sent(sent);
            Ok::<_, std::io::Error>(chunk)
        });
        let mut req = self.s3.put(url).header(reqwest::header::CONTENT_LENGTH, len).body(reqwest::Body::wrap_stream(stream));
        for (k, v) in headers {
            req = req.header(k, v);
        }
        let res = req.send().await.map_err(|e| anyhow!("parte {part}: {e}"))?;
        let status = res.status();
        if status != reqwest::StatusCode::OK {
            return Err(UploadError::S3 { status: status.as_u16(), part });
        }
        Ok(res.headers().get("etag").and_then(|v| v.to_str().ok()).unwrap_or_default().to_owned())
    }

    // MARK: - Miniatura

    async fn upload_thumbnail(&self, state: &UploadState, slug: &str) -> Result<(), UploadError> {
        let (file, meta) = (state.file.clone(), state.meta.clone());
        let jpg = tokio::task::spawn_blocking(move || media::thumbnail(&file, &meta)).await.map_err(|e| anyhow!(e))??;
        let target = self.api.thumbnail_target(slug).await?;
        let headers: Vec<_> = target.headers.into_iter().collect();
        self.put(&target.upload_url, jpg, 0, &headers, |_| {}).await.map(drop)
    }
}

fn read_range(file: &Path, offset: u64, len: u64) -> Result<Vec<u8>> {
    let mut f = std::fs::File::open(file)?;
    f.seek(SeekFrom::Start(offset))?;
    let mut buf = vec![0; len as usize];
    f.read_exact(&mut buf)?;
    Ok(buf)
}
