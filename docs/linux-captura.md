# Notas de captura en Linux

Hallazgos no obvios de la Fase 1, obtenidos en la máquina de desarrollo original.
Varios dependen del hardware: en otra máquina conviene volver a medir.

## Máquina original

- Hyprland/Wayland (Omarchy), i5-6500 de 4 núcleos, GPU AMD FirePro M6100.
- No hay `vah264enc` (sin VA-API utilizable) → se codifica con `x264enc` por CPU.
- Monitor 4K (3840×2160, BGRA).
- Las notificaciones las sirve quickshell.

## Resolución y rendimiento

- x264 no codifica 4K30 en tiempo real en esa CPU: se acumulaba retraso y al
  detener se colgaba. Se escala a `max_height` (1080 por defecto en `config.json`)
  usando `stream.size()` del portal.
- Con movimiento en pantalla, el escalado 4K→1080p no llegaba a tiempo real →
  `pipewiresrc` no devolvía buffers → xdph daba "Out of buffers" y renegociaba en
  bucle → el EOS nunca llegaba, `send_event` bloqueaba el hilo de tokio y la
  grabación quedaba en `stopping` con un MP4 de 0 bytes.
  Arreglo: colas `leaky=downstream` tras `pipewiresrc` y antes del encoder; EOS y
  `set_state(Null)` en hilos aparte con timeout (`set_state(Null)` puede bloquear,
  va en `spawn_blocking`). Detener tarda ~0,3 s.
- Escalado: `nearest` dejaba el texto pixelado → ahora `videoscale method=bilinear`
  en BGRA (4K→1080p es 2:1, equivale a promediar 2×2) + `queue` + `videoconvert`.
  Cuesta ~0,5 núcleos. Bitrate 8 Mbps.
- Escalado por GL (`glcolorscale`) DESCARTADO: la GPU ya iba al ~100 % solo
  componiendo 4K → el video bajaba a 14 fps.
- Resultado: ~23–24 fps con movimiento (se descartan frames). Huecos de ~1 s en
  pantalla estática son normales. La fluidez no es prioridad: se graban pantallas,
  no videos.

## Comportamientos esperados

- Con `mp4mux faststart=true` el archivo pesa 0 bytes mientras se graba; se escribe
  todo al EOS.
- El restore token del portal se guarda en `~/.local/state/mis-looms/restore_token`.
  Es por máquina: en un ordenador nuevo el portal vuelve a pedir la pantalla una vez.
  En la máquina original xdph tenía `allow_token_by_default = true` y el picker
  `hyprland-preview-share-picker`.

## Dependencias Rust

- ashpd 0.13: `set_sources` requiere `BitFlags::from(SourceType::Monitor)`
  (crate `enumflags2`).
- zbus/ashpd con la feature `tokio` y sin default features.

## Audio

- El usuario graba solo el micrófono: `"record_system_audio": false` en
  `~/.config/mis-looms/config.json` (desde 2026-10-19 también es el valor por defecto).
- En el iMac original, Mic Boost +20 dB y Capture +12 dB metían un ruido grave de
  fondo; bajarlos si molesta.

## Diagnóstico

```
GST_DEBUG="2,pipewiresrc:5,basesrc:4,qtmux:4" GST_DEBUG_FILE=/tmp/gst.log mis-looms
```

Contar `stream state paused` en el log para detectar renegociaciones.
`ptrace_scope=1` impide usar gdb sin sudo.

## Pausa (2026-10-19)

- No se pausa el pipeline (las fuentes en vivo y xdph renegocian). Se ponen sondas de buffer en
  `vpause` (cola antes de x264) y `apause` (cola tras `audiomixer`): se descartan los buffers con
  PTS dentro de un tramo en pausa y a los posteriores se les resta lo pausado.
- Las sondas van **después** de `audiomixer`: si se adelantan las marcas antes, audiomixer (en
  vivo, agrega por reloj) considera el audio atrasado y lo tira.
- Verificado: 10,6 s de reloj con 3 s de pausa → MP4 de 7,6 s sin huecos de video ni audio.

## Píldora flotante y Hyprland

- `hl.layer_rule({ ..., no_screen_share = true })` funciona con capas, pero pinta un
  rectángulo negro en la captura en vez de ocultarla: por eso no se usa y la píldora sale en el
  video.
- `hyprctl keyword` ya no sirve con la configuración en Lua; las reglas se aplican con
  `hyprctl eval 'hl.layer_rule({...})'`.
- Una superficie layer-shell no sabe su posición global: para arrastrar se lee el cursor del
  socket de Hyprland (`j/cursorpos`) y se mueven los márgenes.
- Las ventanas de GTK4 no encogen solas: tras cambiar los botones, `set_default_size(1, 1)`.
