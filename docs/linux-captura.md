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
  `~/.config/mis-looms/config.json` (el valor por defecto del código es `true`).
- En el iMac original, Mic Boost +20 dB y Capture +12 dB metían un ruido grave de
  fondo; bajarlos si molesta.

## Diagnóstico

```
GST_DEBUG="2,pipewiresrc:5,basesrc:4,qtmux:4" GST_DEBUG_FILE=/tmp/gst.log mis-looms
```

Contar `stream state paused` en el log para detectar renegociaciones.
`ptrace_scope=1` impide usar gdb sin sudo.
