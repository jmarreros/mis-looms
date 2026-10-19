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
- Página pública `/v/{slug}`: con sesión de administrador muestra el detalle del panel (copiar
  enlace, renombrar, eliminar; sus visitas no cuentan); sin sesión, la página pública sin esas
  opciones. Tras grabar, la app de macOS abre esta URL en el navegador.
- Reproductor (`partials/reproductor.blade.php` + `public/js/reproductor.js`, en la página pública
  y en el detalle) con **controles propios** (reproducir, volumen, tiempo, barra, velocidad,
  pantalla completa; atajos espacio/k, f, m, flechas). Al terminar muestra «Ver de nuevo» en el
  centro, también en pantalla completa, porque esta se hace sobre el marco (video + capas): la
  nativa del `<video>` no deja poner nada encima, y con los controles nativos Chrome dejaba su
  botón de pantalla completa (deshabilitado) además del propio. Sin JS quedan los nativos.
  Probado con Playwright en Chrome, Firefox y WebKit (para buscar en la barra, el servidor de
  pruebas debe admitir peticiones por rangos; `python -m http.server` no las admite).
- CSS y JS se enlazan con `?v=filemtime(...)` para que el navegador no use copias viejas.
- Panel web: siempre en modo oscuro, según el diseño de Claude Design (sistema "Organic":
  fondo `#1c1a17`, acento terracota `#d67f48`, salvia de segundo color, títulos Caprasimo
  y texto Figtree de Google Fonts, botones y campos en píldora). Todo en
  `server/public/css/app.css`.

## Estado (2026-10-19)

**Fase 1 — HECHA y probada.** `linux/` en Rust (todavía sin GTK):
- Daemon `mis-looms` con icono en la bandeja (ksni) y servicio D-Bus
  `org.mislooms.Recorder`; se controla con `mis-looms toggle|start|stop|status`.
- Portal ScreenCast con ashpd 0.13 y restore token.
- GStreamer → MP4 H.264 (x264) + AAC (fdkaac), faststart, escalado a 1080p,
  8 Mbps. Videos en `~/Videos/mis-looms/`.
- Pendiente de confirmar: que las notificaciones se vean tras el último arreglo.

**App macOS (adelantada, 2026-10-12) — HECHA y probada.** `macos/`: paquete SwiftPM (sin
Xcode, solo Command Line Tools), app de barra de menú, ScreenCaptureKit + AVAssetWriter.
Atajo global ⌥⇧L (inicia y, de nuevo, finaliza; ⌘⇧L chocaba con Loom). MP4 H.264 + AAC estéreo, ≤1080p,
faststart, en `~/Movies/mis-looms/` (verificado con ffprobe). Audio del sistema
desactivado por defecto (opción de menú; sin mezclar aún, ver TODO en `Recorder.swift`).
Compilar: `macos/crear-certificado.sh` (una vez) + `macos/compilar.sh`; el certificado
"Mis Looms Dev" mantiene los permisos entre compilaciones. Detalles: [macos/README.md](macos/README.md).
Pendiente: mezclar audio del sistema en una sola pista; cuenta regresiva y pausa.

**Fase 2 — HECHA (2026-10-12).** S3 configurado y verificado (`mis-looms-jmarreros`,
us-east-1) y backend Laravel 13.35 en `server/` (Blade puro, CSS a mano sin Vite/Node):
API Sanctum multipart (`docs/api.md`), página pública `/v/{slug}` con Open Graph, panel
(login, listado con búsqueda, renombrar, eliminar con borrado en S3, token de la app),
comandos `mislooms:crear-usuario` y `mislooms:limpiar-subidas` (cron horario). 23 pruebas
PHPUnit con almacenamiento falso; flujo real probado contra S3 (1 y 2 partes, abort).
Despliegue y desarrollo: `docs/despliegue.md`. Claves del usuario IAM `mis-looms-laravel`
rotadas y verificadas contra S3 el 2026-10-13. Pendiente: desplegar en cPanel.

**Fase 3, macOS — HECHA (2026-10-13).** La app sube sola al terminar la grabación: ventana de
Ajustes (URL + token en Llavero, "Probar conexión"), multipart a S3 con progreso, 3 partes en
paralelo y reintentos, miniatura del segundo 1, enlace al portapapeles + notificación clicable,
cancelar/reintentar y reanudación al abrir la app (estado en `~/Library/Application Support/
Mis Looms/subidas/`). Añadido `GET /api/ping` al servidor. Probado de punta a punta contra S3
real con un MP4 de 58 MB (6 partes, idéntico byte a byte), con `kill -9` + reanudar, Ctrl+C
(aborta), subida cerrada por el servidor (empieza de cero) y token inválido. Ver `macos/README.md`.
Sin probar: los reintentos por corte de red o URL caducada (403), y la interfaz (menú, ventana
de Ajustes, clic en la notificación) no se verificó automáticamente.

**Pulido de macOS + panel (2026-10-13), hecho:**
- App de macOS: ventana de Ajustes rediseñada (campos en píldora de una línea, botones grandes,
  aviso verde/rojo); un solo atajo ⌥⇧L que alterna; al finalizar muestra «Finalizando…» →
  «Subiendo N%» (+ notificación) y abre el enlace en el navegador (opción de menú, solo con
  grabaciones de la sesión). Instalada en `/Applications/Mis Looms.app` (copiar con `ditto`
  tras `compilar.sh`).
- Panel Laravel rehecho con el diseño de Claude Design (oscuro, naranja terracota, Caprasimo +
  Figtree): login, listado con buscador y, en cada tarjeta, copiar enlace / renombrar / eliminar
  (vuelve a la misma página; no deja páginas vacías), detalle del video, token. 33 pruebas.
- Logo naranja en `marca/` (app, favicon, panel).

**Controles flotantes y pausa en macOS (2026-10-14), hecho sin probar grabando:** píldora
siempre visible (`PanelFlotante.swift`: grabar, cronómetro, pausar/reanudar, finalizar,
descartar en pausa con doble clic de confirmación, salir en reposo; excluida del video) porque el atajo ⌥⇧L no le funciona bien al usuario; pausa en `Recorder`
descartando muestras y restando el tiempo pausado. Verificado solo el dibujo del panel fuera de
pantalla; falta que el usuario pruebe una grabación con pausas (continuidad del audio/video).

**Cuenta regresiva en macOS (2026-10-14), hecha sin probar grabando:** 3, 2, 1 en el centro de la
pantalla (`CuentaRegresiva.swift`) y en el panel, cancelable; opción en el menú (activa por defecto).

**Decisión (2026-10-13): la app de Linux queda en pausa**; el foco es la app de macOS y el
backend Laravel. **Retomada el 2026-10-19** (ver abajo).

**App de Linux al nivel de macOS (2026-10-19), hecha.** `linux/` (Rust): GTK4 + gtk4-layer-shell
en el hilo principal y el controlador en tokio. Píldora flotante (grabar, cronómetro, pausa,
descartar con doble clic, finalizar, salir; se arrastra con el cursor global de Hyprland),
cuenta regresiva 3-2-1 (el portal se pide antes), pausa con sondas antes de los encoders,
subida multipart igual que macOS (estado en `~/.local/state/mis-looms/subidas/`, reanuda al
abrir), miniatura y metadatos con GStreamer, enlace con `wl-copy` + notificación + navegador,
ventana de Ajustes (URL en `config.json`, token en el llavero con `secret-tool`), bandeja con
el mismo menú, CLI `subir`/`reanudar`/`ajustes`/`pause`. Probado: grabación con pausa (MP4
continuo, sin huecos, audio y video alineados) y subida contra un servidor simulado local
(4 partes idénticas byte a byte, reintento, `kill -9` + reanudar, Ctrl+C aborta, token
inválido, daemon de punta a punta). **Falta:** configurar URL + token en este ordenador y
probar contra producción; arrastrar la píldora con el ratón; clic en la notificación.
La píldora **sí sale en el video** (Wayland no deja excluirla; `no_screen_share` de Hyprland
pinta un rectángulo negro).

**Despliegue (2026-10-14), hecho:** en producción en https://jmarreros.com/mis-looms (VPS de
Hostinger, nginx + php-fpm 8.4, junto a Mis Videos; no es cPanel). Base SQLite copiada de local,
S3 y correo con Resend verificados desde el servidor. Detalles y cómo actualizar: `docs/despliegue.md`.

La app de macOS ya apunta a `https://jmarreros.com/mis-looms` («Probar conexión» correcto, con el
token copiado de la base local).

**Siguiente:** hacer una grabación real de punta a punta contra producción. Después:
abrir la app al iniciar sesión, mezclar el audio del sistema con el
micrófono, script `instalar.sh`, videos privados («solo yo») y cambio de contraseña desde el panel.

Al terminar una fase o tomar una decisión nueva, actualizar esta sección.

## Preparar un ordenador nuevo (Linux)

1. Instalar dependencias según `linux/README.md`.
2. `linux/instalar.sh`: compila, enlaza `~/.local/bin/mis-looms` y crea el acceso «Mis Looms»
   en el lanzador de Omarchy (con icono).
3. Abrir la app una vez para que cree `~/.config/mis-looms/config.json`
   (`"record_system_audio": false` ya es el valor por defecto, preferencia del usuario).
4. Bandeja › Ajustes… (o `mis-looms ajustes`): URL `https://jmarreros.com/mis-looms` + token.
5. Opcional, Omarchy (Hyprland en Lua): `o.launch_on_start("mis-looms")` en `autostart.lua` y
   `o.bind("SUPER + SHIFT + R", "Mis Looms", "mis-looms toggle")` en `bindings.lua`.
6. La primera grabación pide elegir la pantalla (el restore token es por máquina).
