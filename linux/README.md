# Mis Looms — app de Linux

Grabador de pantalla completa para Wayland (Hyprland) usando el portal
`xdg-desktop-portal` ScreenCast + PipeWire + GStreamer. Graba pantalla,
micrófono y audio del sistema en MP4 (H.264 + AAC, faststart).

## Dependencias (Arch)

```
sudo pacman -S --needed rustup gst-plugins-good gst-plugins-ugly gst-plugins-bad gst-libav \
  gst-plugin-pipewire xdg-desktop-portal-hyprland
```

## Compilar e instalar

```
cargo build --release
install -Dm755 target/release/mis-looms ~/.local/bin/mis-looms
```

## Uso

- `mis-looms` — inicia el daemon (icono en la bandeja de Waybar).
- `mis-looms toggle | start | stop | status` — controla el daemon por D-Bus.

En `~/.config/hypr/hyprland.conf` (o `bindings.conf` en Omarchy):

```
exec-once = mis-looms
bind = SUPER SHIFT, R, exec, mis-looms toggle
```

La primera vez el portal pide elegir la pantalla; si marcas "permitir
restaurar" (restore token), las siguientes grabaciones empiezan directo.

Los videos se guardan en `~/Videos/mis-looms/`. Configuración en
`~/.config/mis-looms/config.json` (micrófono, audio del sistema, fps, bitrate).
