use std::path::Path;

use anyhow::{Context, Result, anyhow};
use gstreamer as gst;
use gstreamer::prelude::*;
use gstreamer_app as gst_app;
use gstreamer_pbutils as gst_pbutils;

use crate::api::Metadata;

/// Procesamiento en el cliente (el hosting no tiene ffmpeg): metadatos y miniatura del MP4.
/// Funciones bloqueantes: llamarlas desde `spawn_blocking`.
pub fn metadata(path: &Path) -> Metadata {
    let mut meta = Metadata::default();
    let Ok(uri) = gst::glib::filename_to_uri(path, None) else { return meta };
    let Ok(discoverer) = gst_pbutils::Discoverer::new(gst::ClockTime::from_seconds(15)) else { return meta };
    let Ok(info) = discoverer.discover_uri(&uri) else { return meta };
    if let Some(d) = info.duration() {
        meta.duration = Some((d.mseconds() as f64 / 100.0).round() / 10.0);
    }
    if let Some(v) = info.video_streams().first() {
        meta.width = Some(v.width());
        meta.height = Some(v.height());
    }
    meta
}

/// JPG del segundo 1 (o de la mitad si el video dura menos), de hasta 1280×720.
pub fn thumbnail(path: &Path, meta: &Metadata) -> Result<Vec<u8>> {
    let (w, h) = match (meta.width, meta.height) {
        (Some(w), Some(h)) if w > 0 && h > 0 => {
            let scale = (1280.0 / w as f64).min(720.0 / h as f64).min(1.0);
            (((w as f64 * scale) as u32) & !1, ((h as f64 * scale) as u32) & !1)
        }
        _ => (1280, 720),
    };
    let location = path.to_str().ok_or_else(|| anyhow!("ruta no UTF-8"))?;
    let pipeline = gst::parse::launch(&format!(
        "filesrc location=\"{location}\" ! decodebin ! videoconvert ! videoscale method=bilinear \
         ! video/x-raw,width={w},height={h},pixel-aspect-ratio=1/1 ! jpegenc quality=80 \
         ! appsink name=sink sync=false"
    ))?
    .downcast::<gst::Pipeline>()
    .map_err(|_| anyhow!("el pipeline no es un gst::Pipeline"))?;
    let sink = pipeline
        .by_name("sink")
        .and_then(|e| e.downcast::<gst_app::AppSink>().ok())
        .ok_or_else(|| anyhow!("sin appsink"))?;

    let result = (|| -> Result<Vec<u8>> {
        pipeline.set_state(gst::State::Paused)?;
        wait_preroll(&pipeline)?;
        let second = (meta.duration.unwrap_or(2.0) / 2.0).min(1.0);
        pipeline.seek_simple(
            gst::SeekFlags::FLUSH | gst::SeekFlags::ACCURATE,
            gst::ClockTime::from_mseconds((second * 1000.0) as u64),
        )?;
        wait_preroll(&pipeline)?;
        let sample = sink.pull_preroll().context("no se obtuvo el fotograma")?;
        let buffer = sample.buffer().ok_or_else(|| anyhow!("fotograma vacío"))?;
        Ok(buffer.map_readable()?.as_slice().to_vec())
    })();
    let _ = pipeline.set_state(gst::State::Null);
    result
}

fn wait_preroll(pipeline: &gst::Pipeline) -> Result<()> {
    let (res, _, _) = pipeline.state(gst::ClockTime::from_seconds(15));
    res.map(drop).map_err(|_| {
        let bus = pipeline.bus().expect("un pipeline siempre tiene bus");
        match bus.pop_filtered(&[gst::MessageType::Error]).as_ref().map(|m| m.view()) {
            Some(gst::MessageView::Error(e)) => anyhow!("{}", e.error()),
            _ => anyhow!("no se pudo leer el video"),
        }
    })
}
