# Mis Looms — app de Linux

Versión nativa para Linux (Wayland, probada en Hyprland/Omarchy) con las mismas funciones que la
app de macOS. Rust + GTK4 + gtk4-layer-shell para la interfaz, portal `xdg-desktop-portal`
ScreenCast + PipeWire + GStreamer para grabar, y el mismo contrato de API (`docs/api.md`) para
subir. Graba la pantalla completa + micrófono (+ audio del sistema opcional, mezclado en una sola
pista) a MP4 (H.264 8 Mbps máx. 1080p, AAC, faststart) en `~/Videos/mis-looms/`.

## Dependencias (Arch)

```
sudo pacman -S --needed rustup gtk4 gtk4-layer-shell libsecret wl-clipboard \
  gst-plugins-good gst-plugins-ugly gst-plugins-bad gst-libav gst-plugin-pipewire \
  xdg-desktop-portal-hyprland
```

Hace falta un servicio de llavero (Secret Service: gnome-keyring o KWallet) para guardar el token.

## Compilar e instalar

```
./instalar.sh
```

Compila y deja `~/.local/bin/mis-looms` (enlace al binario), el acceso «Mis Looms» en el
lanzador (`~/.local/share/applications/mis-looms.desktop`, desde `mis-looms.desktop`) y el
icono (`marca/logo.svg`). Se vuelve a ejecutar para actualizar. Abrir la app desde el lanzador
con el daemon ya en marcha muestra los Ajustes; el acceso tiene además las acciones
«Iniciar o finalizar grabación» y «Ajustes».

## Uso

- `mis-looms` — inicia el daemon: icono en la bandeja, controles flotantes y servicio D-Bus
  `org.mislooms.Recorder`.
- `mis-looms toggle | start | stop | pause | status | ajustes` — controla el daemon por D-Bus
  (`toggle` inicia, cancela la cuenta regresiva o finaliza según el estado; `pause` alterna).

En Omarchy (configuración en Lua), en `~/.config/hypr/autostart.lua` y `bindings.lua`:

```lua
o.launch_on_start("mis-looms")
o.bind("SUPER + SHIFT + R", "Mis Looms", "mis-looms toggle")
```

La primera vez el portal pide elegir la pantalla; si marcas "permitir restaurar" (restore
token), las siguientes grabaciones empiezan directo.

### Interfaz

- **Controles flotantes** (`ui.rs`, capa *overlay* de layer-shell): una píldora siempre encima,
  abajo a la izquierda. En reposo «● Grabar» (y «Subiendo N %» si hay una subida) y una ✕ para
  salir; grabando, el cronómetro en rojo con pausar y finalizar; en pausa, en amarillo, con
  reanudar, descartar (pide un segundo clic en 4 s) y finalizar. Se arrastra desde el asa ⠿ o el
  cronómetro y recuerda su posición. Se oculta con **Mostrar controles flotantes**.
  **Sí sale en el video**: Wayland no permite excluir una ventana de la captura de pantalla
  completa, y la regla `no_screen_share` de Hyprland pinta un rectángulo negro en su lugar.
- **Cuenta regresiva**: 3, 2, 1 en el centro de la pantalla con un anillo, y «Empieza en N» en la
  píldora con ✕ para cancelar. El portal se pide antes, así que el selector de pantalla no se
  come la cuenta, y la captura empieza al ocultarse (no sale en el video). Se desactiva en el menú.
- **Pausa**: se descartan los buffers antes de los encoders y a los siguientes se les resta lo
  pausado: el MP4 sale continuo y el cronómetro no cuenta las pausas.
- **Bandeja**: iniciar/finalizar, pausar, descartar, progreso y cancelación de la subida,
  reintentar pendientes, copiar último enlace, opciones (audio del sistema, cuenta regresiva,
  abrir el enlace al terminar, controles flotantes), abrir carpeta, Ajustes… y salir.

Al arrancar en Hyprland, la app aplica en caliente (`hyprctl eval`) dos reglas: sin animación
para sus capas y la ventana de Ajustes flotante y centrada.

## Subida al servidor

1. Bandeja › **Ajustes…** (o `mis-looms ajustes`): URL del servidor (p. ej.
   `https://jmarreros.com/mis-looms`) y token (panel web › Token de la app). "Probar conexión"
   llama a `GET /api/ping`. La URL va en `~/.config/mis-looms/config.json` (`server_url`) y el
   token al llavero (`secret-tool lookup service org.mislooms.Recorder account token-api`).
2. Al finalizar, la píldora muestra «Finalizando…» y luego «Subiendo N %». Sube directo a S3
   (partes de 10 MB, 3 en paralelo, 4 reintentos por parte, vuelve a firmar si S3 da 403), una
   miniatura JPG del segundo 1 (hasta 1280×720, sacada con GStreamer) y cierra la subida.
3. Copia el enlace al portapapeles (`wl-copy`), notifica y **abre el video en el navegador**
   (solo grabaciones de la sesión; opción **Abrir el enlace al terminar**).

Si falla o se cierra la app, el estado queda en `~/.local/state/mis-looms/subidas/` y se
**reanuda al abrir la app** (solo las partes que faltan) o con **Reintentar subidas pendientes**.
Si el servidor ya cerró esa subida, empieza de cero con el mismo archivo. Cancelar la aborta en
el servidor. Salir mientras se graba cierra el MP4 y lo deja en cola para la próxima vez.

Sin interfaz (scripts y pruebas):

```
MISLOOMS_URL=https://tu-dominio MISLOOMS_TOKEN=… mis-looms subir video.mp4
mis-looms reanudar        # reanuda las pendientes · Ctrl+C cancela y aborta en el servidor
```
(`MISLOOMS_ESTADO` cambia la carpeta del estado de subidas; con `MISLOOMS_TOKEN` no se toca
el llavero.)

## Configuración

`~/.config/mis-looms/config.json`: `output_dir`, `record_mic`, `record_system_audio`,
`framerate`, `max_height` (0 = nativa), `video_bitrate_kbps`, `server_url`, `countdown`,
`open_link_after_upload`, `show_panel`, `panel_position` (márgenes izquierdo e inferior).

## Estructura

- `src/main.rs` — controlador (máquina de estados en tokio), D-Bus, cola de subidas, notificaciones.
- `src/recorder.rs` — portal (`Capture`) y pipeline de GStreamer con pausa (`Recording`).
- `src/ui.rs` — GTK4 en el hilo principal: píldora, cuenta regresiva y ventana de Ajustes.
- `src/tray.rs` — icono y menú de la bandeja (StatusNotifierItem con ksni).
- `src/uploader.rs` — multipart a S3 con progreso, reintentos y estado en disco.
- `src/api.rs` — cliente de `docs/api.md`.
- `src/media.rs` — metadatos (Discoverer) y miniatura del MP4.
- `src/config.rs` — configuración, token en el llavero y restore token del portal.
- `src/cli.rs` — modos `subir` / `reanudar` sin interfaz.

Notas de rendimiento y diagnóstico de la captura: [../docs/linux-captura.md](../docs/linux-captura.md).
