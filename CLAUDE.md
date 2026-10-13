# Mis Looms

Clon personal de Loom: apps nativas graban la pantalla completa + micrófono (+ audio
del sistema opcional), suben el MP4 directo a S3 con multipart prefirmado por Laravel
y se obtiene un enlace público `/v/{slug}`. Un solo usuario.

- Plan completo de arquitectura y fases: [docs/PLAN.md](docs/PLAN.md)
- API de las apps y despliegue del servidor: [docs/api.md](docs/api.md), [docs/despliegue.md](docs/despliegue.md)
- Hallazgos de la captura en Linux: [docs/linux-captura.md](docs/linux-captura.md)
- App de macOS (compilar sin Xcode, uso): [macos/README.md](macos/README.md)
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
- Logo en `marca/`: `logo.svg` (degradado naranja `#F6A06B` → `#B2622D`) y `logo-mono.svg`
  (huecos transparentes, para barra de menú/bandeja). macOS los toma al compilar
  (`.icns` + icono plantilla de la barra); el servidor usa una copia en
  `server/public/logo.svg` (favicon, cabecera, login): si cambia el logo, copiarlo de nuevo.
- Panel web: siempre en modo oscuro, según el diseño de Claude Design (sistema "Organic":
  fondo `#1c1a17`, acento terracota `#d67f48`, salvia de segundo color, títulos Caprasimo
  y texto Figtree de Google Fonts, botones y campos en píldora). Todo en
  `server/public/css/app.css`.

## Estado (2026-10-13)

**Fase 1 — HECHA y probada.** `linux/` en Rust (todavía sin GTK):
- Daemon `mis-looms` con icono en la bandeja (ksni) y servicio D-Bus
  `org.mislooms.Recorder`; se controla con `mis-looms toggle|start|stop|status`.
- Portal ScreenCast con ashpd 0.13 y restore token.
- GStreamer → MP4 H.264 (x264) + AAC (fdkaac), faststart, escalado a 1080p,
  8 Mbps. Videos en `~/Videos/mis-looms/`.
- Pendiente de confirmar: que las notificaciones se vean tras el último arreglo.

**App macOS (adelantada, 2026-10-12) — HECHA y probada.** `macos/`: paquete SwiftPM (sin
Xcode, solo Command Line Tools), app de barra de menú, ScreenCaptureKit + AVAssetWriter.
Atajos globales ⌥⇧L (iniciar) y ⌘⇧L (finalizar). MP4 H.264 + AAC estéreo, ≤1080p,
faststart, en `~/Movies/mis-looms/` (verificado con ffprobe). Audio del sistema
desactivado por defecto (opción de menú; sin mezclar aún, ver TODO en `Recorder.swift`).
Compilar: `macos/crear-certificado.sh` (una vez) + `macos/compilar.sh`; el certificado
"Mis Looms Dev" mantiene los permisos entre compilaciones. Detalles: [macos/README.md](macos/README.md).
Pendiente: mezclar audio del sistema en una sola pista; cuenta regresiva y pausa; la
subida a S3 va después de la API (Fase 3, mismo contrato).

**Fase 2 — HECHA (2026-10-12).** S3 configurado y verificado (`mis-looms-jmarreros`,
us-east-1) y backend Laravel 13.35 en `server/` (Blade puro, CSS a mano sin Vite/Node):
API Sanctum multipart (`docs/api.md`), página pública `/v/{slug}` con Open Graph, panel
(login, listado con búsqueda, renombrar, eliminar con borrado en S3, token de la app),
comandos `mislooms:crear-usuario` y `mislooms:limpiar-subidas` (cron horario). 23 pruebas
PHPUnit con almacenamiento falso; flujo real probado contra S3 (1 y 2 partes, abort).
Despliegue y desarrollo: `docs/despliegue.md`. Pendiente: rellenar claves del usuario IAM
`mis-looms-laravel` en `server/.env` y desplegar en cPanel.

**Fase 3, macOS — HECHA (2026-10-13).** La app sube sola al terminar la grabación: ventana de
Ajustes (URL + token en Llavero, "Probar conexión"), multipart a S3 con progreso, 3 partes en
paralelo y reintentos, miniatura del segundo 1, enlace al portapapeles + notificación clicable,
cancelar/reintentar y reanudación al abrir la app (estado en `~/Library/Application Support/
Mis Looms/subidas/`). Añadido `GET /api/ping` al servidor. Probado de punta a punta contra S3
real con un MP4 de 58 MB (6 partes, idéntico byte a byte), con `kill -9` + reanudar, Ctrl+C
(aborta), subida cerrada por el servidor (empieza de cero) y token inválido. Ver `macos/README.md`.
Sin probar: los reintentos por corte de red o URL caducada (403), y la interfaz (menú, ventana
de Ajustes, clic en la notificación) no se verificó automáticamente.
Pendiente: desplegar el servidor en cPanel; rotar las claves del usuario IAM (se mostraron en
una conversación); pausa y cuenta regresiva; mezclar audio del sistema.

**Siguiente: subida en Linux** (mismo flujo en Rust: multipart con progreso y reintentos,
miniatura, enlace al portapapeles, notificación, ventana GTK4 con URL + token en el keyring).

**Después:** pausa y cuenta regresiva en la grabación, mezclar el audio del sistema con el
micrófono, y desplegar en cPanel (`docs/despliegue.md`).

Al terminar una fase o tomar una decisión nueva, actualizar esta sección.

## Preparar un ordenador nuevo

1. Instalar dependencias y compilar según `linux/README.md`.
2. `ln -s "$PWD/linux/target/release/mis-looms" ~/.local/bin/mis-looms`
3. Ejecutar `mis-looms` una vez para que cree `~/.config/mis-looms/config.json` y
   ajustar `"record_system_audio": false` (preferencia del usuario).
4. Opcional, en la config de Hyprland: `exec-once = mis-looms` y
   `bind = SUPER SHIFT, R, exec, mis-looms toggle`.
5. La primera grabación pide elegir la pantalla (el restore token es por máquina).
