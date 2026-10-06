use std::os::fd::{AsRawFd, OwnedFd};
use std::path::PathBuf;
use std::time::Duration;

use anyhow::{Context, Result, anyhow};
use enumflags2::BitFlags;
use ashpd::desktop::PersistMode;
use ashpd::desktop::Session;
use ashpd::desktop::screencast::{CursorMode, Screencast, SelectSourcesOptions, SourceType};
use gstreamer as gst;
use gstreamer::prelude::*;

use crate::config::{self, Config};

/// Una grabación en curso: pipeline de GStreamer + sesión del portal.
pub struct Recording {
    pub path: PathBuf,
    pipeline: gst::Pipeline,
    session: Session<Screencast>,
    // El fd de PipeWire debe vivir mientras dure el pipeline.
    _fd: OwnedFd,
}

/// Resultado final que entrega el hilo que vigila el bus de GStreamer.
pub type Finished = Result<()>;

impl Recording {
    /// Pide la pantalla al portal y arranca el pipeline. `on_finish` recibe
    /// el resultado cuando el pipeline termina (EOS tras `stop`, o error).
    pub async fn start(config: &Config, on_finish: impl FnOnce(Finished) + Send + 'static) -> Result<Self> {
        let proxy = Screencast::new().await.context("portal ScreenCast no disponible")?;
        let session = proxy.create_session(Default::default()).await?;
        let token = config::load_restore_token();
        proxy
            .select_sources(
                &session,
                SelectSourcesOptions::default()
                    .set_cursor_mode(CursorMode::Embedded)
                    .set_sources(BitFlags::from(SourceType::Monitor))
                    .set_multiple(false)
                    .set_restore_token(token.as_deref())
                    .set_persist_mode(PersistMode::ExplicitlyRevoked),
            )
            .await?;
        let response = proxy
            .start(&session, None, Default::default())
            .await?
            .response()
            .context("selección de pantalla cancelada")?;
        config::save_restore_token(response.restore_token());
        let stream = response.streams().first().ok_or_else(|| anyhow!("el portal no devolvió ningún stream"))?.to_owned();
        let fd = proxy.open_pipe_wire_remote(&session, Default::default()).await?;

        std::fs::create_dir_all(&config.output_dir)?;
        let path = config
            .output_dir
            .join(format!("{}.mp4", chrono::Local::now().format("%Y-%m-%d_%H-%M-%S")));

        let size = output_size(stream.size(), config.max_height);
        let description = pipeline_description(config, fd.as_raw_fd(), stream.pipe_wire_node_id(), size, &path)?;
        let pipeline = gst::parse::launch(&description)?
            .downcast::<gst::Pipeline>()
            .map_err(|_| anyhow!("el pipeline no es un gst::Pipeline"))?;

        let bus = pipeline.bus().expect("un pipeline siempre tiene bus");
        pipeline.set_state(gst::State::Playing)?;
        std::thread::spawn(move || on_finish(watch_bus(&bus)));

        Ok(Self { path, pipeline, session, _fd: fd })
    }

    /// Pide terminar: el EOS hace que mp4mux escriba el índice y cierre el archivo.
    /// `send_event` puede bloquear si el pipeline está trabado, así que va en otro hilo.
    pub fn stop(&self) {
        let pipeline = self.pipeline.clone();
        std::thread::spawn(move || pipeline.send_event(gst::event::Eos::new()));
    }

    /// Libera el pipeline y la sesión del portal (llamar tras `on_finish`).
    pub async fn close(self) {
        // set_state(Null) puede bloquear si el pipeline quedó trabado: en un hilo
        // aparte y con límite de tiempo, para no dejar el daemon colgado.
        let pipeline = self.pipeline;
        let null = std::thread::spawn(move || pipeline.set_state(gst::State::Null));
        let waited = tokio::time::timeout(Duration::from_secs(5), async {
            while !null.is_finished() {
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        })
        .await;
        if waited.is_err() {
            eprintln!("el pipeline no se detuvo en 5 s; se abandona");
        }
        let _ = self.session.close().await;
    }
}

fn watch_bus(bus: &gst::Bus) -> Finished {
    use gst::MessageView;
    for msg in bus.iter_timed(gst::ClockTime::NONE) {
        match msg.view() {
            MessageView::Eos(..) => return Ok(()),
            MessageView::Error(err) => {
                let src = msg.src().map(|s| s.path_string().to_string()).unwrap_or_default();
                return Err(anyhow!("{src}: {} ({:?})", err.error(), err.debug()));
            }
            _ => {}
        }
    }
    Err(anyhow!("el bus de GStreamer se cerró inesperadamente"))
}

/// Devuelve el primer elemento disponible de la lista.
fn first_available<'a>(candidates: &[&'a str]) -> Option<&'a str> {
    candidates.iter().copied().find(|name| gst::ElementFactory::find(name).is_some())
}

/// Tamaño de salida: escala a `max_height` (p.ej. 4K → 1080p) manteniendo el aspecto.
/// x264 en CPU no codifica 4K en tiempo real, y 1080p es suficiente para compartir.
fn output_size(source: Option<(i32, i32)>, max_height: u32) -> Option<(u32, u32)> {
    let (w, h) = source.filter(|(w, h)| *w > 0 && *h > 0)?;
    let (w, h) = (w as u32, h as u32);
    let (w, h) = if max_height > 0 && h > max_height { (w * max_height / h, max_height) } else { (w, h) };
    // I420/H.264 exigen dimensiones pares.
    Some((w & !1, h & !1))
}

fn pipeline_description(
    config: &Config,
    fd: i32,
    node_id: u32,
    size: Option<(u32, u32)>,
    path: &std::path::Path,
) -> Result<String> {
    let fps = config.framerate;
    let kbps = config.video_bitrate_kbps;
    let encoder = match first_available(&["vah264enc", "x264enc", "openh264enc"]) {
        Some("vah264enc") => format!("vah264enc bitrate={kbps} key-int-max={}", fps * 2),
        Some("x264enc") => {
            format!("x264enc tune=zerolatency speed-preset=veryfast bitrate={kbps} key-int-max={}", fps * 2)
        }
        Some(other) => format!("{other} bitrate={}", kbps * 1000),
        None => return Err(anyhow!("no hay encoder H.264 (instala gst-plugins-ugly)")),
    };
    let scale = match size {
        Some((w, h)) => format!(",width={w},height={h},pixel-aspect-ratio=1/1"),
        None => String::new(),
    };
    let location = path.to_str().ok_or_else(|| anyhow!("ruta de salida no UTF-8"))?;

    // Escalar primero en BGRA (bilineal: en 4K→1080p promedia bloques 2×2, texto
    // suave) y convertir a I420 ya en 1080p, cada paso en su hilo. Convertir en 4K
    // o usar nearest-neighbour (texto dentado) salía peor. No se usa la GPU por
    // OpenGL: el compositor ya la tiene al ~100 % y el video se congelaba.
    let convert = format!(
        "videoscale n-threads=2 method=bilinear ! video/x-raw{scale} \
         ! queue max-size-buffers=2 ! videoconvert n-threads=2 dither=none"
    );
    // Colas leaky: si la CPU no da abasto se descartan frames en vez de bloquear
    // pipewiresrc. Si se bloquea, xdph se queda sin buffers ("Out of buffers"),
    // renegocia el stream en bucle, el video deja de fluir y el EOS nunca llega.
    let leaky = "queue max-size-buffers=3 max-size-bytes=0 max-size-time=0 leaky=downstream";
    let mut desc = format!(
        "mp4mux name=mux faststart=true ! filesink location=\"{location}\" \
         pipewiresrc fd={fd} path={node_id} do-timestamp=true keepalive-time=1000 always-copy=true \
         ! {leaky} ! {convert} ! video/x-raw,format=I420{scale} ! videorate ! video/x-raw,framerate={fps}/1 \
         ! {leaky} ! {encoder} ! video/x-h264,profile=high ! h264parse ! queue ! mux.video_0 "
    );

    let mut audio_sources = Vec::new();
    if config.record_mic {
        audio_sources.push("pulsesrc");
    }
    if config.record_system_audio {
        audio_sources.push("pulsesrc device=@DEFAULT_MONITOR@");
    }
    if !audio_sources.is_empty() {
        let aac = match first_available(&["fdkaacenc", "avenc_aac", "voaacenc"]) {
            Some("fdkaacenc") => "fdkaacenc bitrate=128000",
            Some("avenc_aac") => "avenc_aac bitrate=128000",
            Some(other) => other,
            None => return Err(anyhow!("no hay encoder AAC (instala gst-libav)")),
        };
        desc.push_str(&format!(
            "audiomixer name=amix ! audioconvert ! audioresample ! audio/x-raw,rate=48000,channels=2 \
             ! {aac} ! aacparse ! queue ! mux.audio_0 "
        ));
        for src in audio_sources {
            desc.push_str(&format!("{src} ! queue ! audioconvert ! audioresample ! amix. "));
        }
    }
    Ok(desc)
}
