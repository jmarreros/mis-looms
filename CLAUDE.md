# Mis Looms

Clon personal de Loom: apps nativas graban la pantalla completa + micrófono (+ audio
del sistema opcional), suben el MP4 directo a S3 con multipart prefirmado por Laravel
y se obtiene un enlace público `/v/{slug}`. Un solo usuario.

- Plan completo de arquitectura y fases: [docs/PLAN.md](docs/PLAN.md)
- Hallazgos de la captura en Linux: [docs/linux-captura.md](docs/linux-captura.md)
- App de Linux (dependencias, compilar, uso): [linux/README.md](linux/README.md)

## Decisiones tomadas

- Apps 100 % nativas por sistema operativo. Linux primero; macOS (Swift +
  ScreenCaptureKit) en la segunda parte.
- Backend: Laravel 13 con vistas Blade puras (sin Livewire ni Filament).
- Hosting compartido cPanel con SSH + cron: sin workers ni ffmpeg, el video nunca
  pasa por el servidor; el procesamiento (miniatura, metadatos) se hace en el cliente.
- Almacenamiento en Amazon S3 con lectura pública por bucket policy.
- El repositorio es PÚBLICO (github.com/jmarreros/mis-looms): no subir secretos
  (`server/.env`, claves de AWS, tokens). Rama principal: `master`.
- Todo el texto (código, comentarios, documentación, mensajes) va en español.

## Estado (2026-10-11)

**Fase 1 — HECHA y probada.** `linux/` en Rust (todavía sin GTK):
- Daemon `mis-looms` con icono en la bandeja (ksni) y servicio D-Bus
  `org.mislooms.Recorder`; se controla con `mis-looms toggle|start|stop|status`.
- Portal ScreenCast con ashpd 0.13 y restore token.
- GStreamer → MP4 H.264 (x264) + AAC (fdkaac), faststart, escalado a 1080p,
  8 Mbps. Videos en `~/Videos/mis-looms/`.
- Pendiente de confirmar: que las notificaciones se vean tras el último arreglo.

**Siguiente: Fase 2** — S3 + API Laravel 13 en `server/` + página pública Blade
`/v/{slug}`. Probar con `curl` y un MP4 de la Fase 1.

**Después:**
- Fase 3: subida desde la app de Linux (multipart con progreso y reintentos,
  miniatura, enlace al portapapeles, notificación, ventana de configuración GTK4
  con URL + token en el keyring).
- Fase 4: panel de administración en Blade.
- Segunda parte: app de macOS con el mismo contrato de API.

Al terminar una fase o tomar una decisión nueva, actualizar esta sección.

## Preparar un ordenador nuevo

1. Instalar dependencias y compilar según `linux/README.md`.
2. `ln -s "$PWD/linux/target/release/mis-looms" ~/.local/bin/mis-looms`
3. Ejecutar `mis-looms` una vez para que cree `~/.config/mis-looms/config.json` y
   ajustar `"record_system_audio": false` (preferencia del usuario).
4. Opcional, en la config de Hyprland: `exec-once = mis-looms` y
   `bind = SUPER SHIFT, R, exec, mis-looms toggle`.
5. La primera grabación pide elegir la pantalla (el restore token es por máquina).
