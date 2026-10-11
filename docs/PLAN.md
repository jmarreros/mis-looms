# Mis Looms — Análisis y plan de arquitectura

## Contexto
Se quiere un clon personal de Loom: grabar **toda la pantalla** (+ micrófono + audio del sistema) con apps **100% nativas** para **Linux (Wayland/Hyprland)** y **macOS**, subir el video a **Amazon S3** con acceso público, y obtener al terminar un **enlace compartible**. Un panel **Laravel** en hosting compartido (cPanel con SSH + cron) gestiona el listado y la administración. Uso personal (un solo usuario).

## Arquitectura general

```
 App nativa (Mac / Linux)            Laravel (hosting compartido)          Amazon S3
 ─────────────────────────           ────────────────────────────          ─────────
 1. Grabar → MP4 local
 2. POST /api/videos  ─────────────▶ crea registro + slug,
                                     inicia multipart upload  ───────────▶ CreateMultipartUpload
    ◀──────────── slug, upload_id, URLs prefirmadas por parte
 3. PUT partes (directo a S3) ──────────────────────────────────────────▶ videos/{slug}.mp4
 4. POST /api/videos/{id}/complete ▶ CompleteMultipartUpload, status=ready
 5. Copia https://dominio/v/{slug} al portapapeles + notificación
```

**Decisión clave:** el video **nunca pasa por el servidor compartido** (límites de `upload_max_filesize`, timeouts, ancho de banda). Laravel solo firma URLs; la app sube directo a S3 con **multipart upload prefirmado** (partes de 10 MB, reintento por parte).

## Componente 1 — Backend Laravel (`server/`)
- **Laravel 13 + PHP 8.3+**, MySQL (lo que ofrezca cPanel). Paquete `aws/aws-sdk-php` (vía `league/flysystem-aws-s3-v3`).
- **Auth:** login web normal (Breeze, un solo usuario creado con seeder/artisan) + **Sanctum personal access token** para las apps nativas (se genera en el panel y se pega en la app).
- **Modelo `Video`:** `id, slug (ulid corto), title, s3_key, thumbnail_key, duration, size, width, height, status (uploading|ready|failed), views, created_at`.
- **API (`routes/api.php`, auth:sanctum):**
  - `POST /api/videos` → crea registro, `CreateMultipartUpload`, devuelve `slug`, `share_url`, `upload_id` y URLs prefirmadas por parte (o endpoint `POST /api/videos/{id}/parts` para pedir lotes).
  - `POST /api/videos/{id}/complete` → recibe ETags, `CompleteMultipartUpload`, marca `ready`.
  - `POST /api/videos/{id}/thumbnail` → URL prefirmada PUT para el JPG.
  - `POST /api/videos/{id}/abort`.
- **Web pública:** `GET /v/{slug}` → página con `<video>` HTML5 apuntando a la URL pública de S3, meta Open Graph (título, miniatura) para previsualización en Slack/WhatsApp, contador de vistas.
- **Panel admin (auth):** listado con miniaturas, buscar, renombrar, copiar enlace, eliminar (borra objeto S3 + registro), regenerar token. Vistas en **Blade puro** (sin Livewire/Filament), CSS simple (Tailwind compilado localmente con Vite y subido en `public/build`, ya que el hosting no necesita Node).
- **Cron:** `* * * * * php artisan schedule:run` → tarea que marca `failed` los `uploading` > 24 h y aborta su multipart. Sin colas persistentes (driver `sync`/`database` procesado por schedule).
- **Despliegue cPanel:** `public/` como document root (o symlink `public_html → server/public`), `composer install --no-dev`, `php artisan migrate --force`, `config:cache`.

## Componente 2 — Amazon S3
- Bucket dedicado, prefijo `videos/` y `thumbs/` con **lectura pública por bucket policy** (`s3:GetObject` en esos prefijos); Block Public Access ajustado solo para policy.
- Usuario IAM para Laravel con permisos mínimos: `PutObject, GetObject, DeleteObject, AbortMultipartUpload, ListMultipartUploadParts` sobre el bucket.
- **Lifecycle rule:** abortar multipart incompletos tras 1 día (evita costos huérfanos).
- `Content-Type: video/mp4` y `faststart` (moov al inicio) para que el video empiece a reproducirse sin descargar todo.
- Opcional fase 2: CloudFront delante del bucket (más barato en egress y más rápido).

## Componente 3 — App macOS (`macos/`, Swift + SwiftUI) — **SEGUNDA PARTE, fuera del alcance actual**
- App de **barra de menú** (`MenuBarExtra`), macOS 13+ (recomendado 14+).
- **Captura:** `ScreenCaptureKit` (`SCShareableContent` → display principal o selector, `SCStream`) con `capturesAudio = true` para **audio del sistema**; micrófono vía `SCStreamConfiguration.captureMicrophone` (macOS 15) o `AVCaptureSession` en 13–14.
- **Codificación:** `AVAssetWriter` → MP4 H.264 (HW, VideoToolbox) + AAC; dos pistas de audio mezcladas o dos tracks (más simple: dos tracks AAC, el `<video>` reproduce la primera → mejor mezclar con `AVAudioEngine` a un único track). `shouldOptimizeForNetworkUse = true` (faststart).
- **Flujo UI:** atajo global (p.ej. ⌥⇧L) iniciar/detener, cuenta regresiva 3 s, indicador de grabación en la barra, pausa/reanudar.
- **Subida:** `URLSession` background, multipart en paralelo (3 partes simultáneas), barra de progreso; al terminar `NSPasteboard` + `UNUserNotification` con el enlace.
- **Miniatura:** `AVAssetImageGenerator` en t=1s → JPG.
- **Config:** URL del servidor + token en **Keychain**.
- Permisos: Screen Recording + Micrófono (Info.plist `NSMicrophoneUsageDescription`). Firmado/notarizado con Developer ID si se distribuye fuera de la máquina propia.

## Componente 4 — App Linux (`linux/`, Rust + GTK4/libadwaita)
En Wayland/Hyprland **no se puede capturar la pantalla directamente**: hay que usar el **portal `xdg-desktop-portal` ScreenCast** (en Hyprland lo implementa `xdg-desktop-portal-hyprland`), que entrega un stream **PipeWire**.
- **Crates:** `gtk4`/`libadwaita` (UI + icono en bandeja vía `ksni`/StatusNotifierItem, que Waybar soporta), `ashpd` (portal ScreenCast → `node_id` + fd PipeWire), `gstreamer-rs`, `reqwest` (subida), `keyring` (token en Secret Service).
- **Pipeline GStreamer:**
  ```
  pipewiresrc fd=… path=<node_id> ! videoconvert ! vah264enc|x264enc ! h264parse ! mux.
  pulsesrc device=@DEFAULT_SOURCE@   ─┐
  pulsesrc device=@DEFAULT_MONITOR@  ─┴ audiomixer ! audioconvert ! fdkaacenc|avenc_aac ! mux.
  mp4mux name=mux faststart=true ! filesink location=…
  ```
  (`pulsesrc` funciona sobre `pipewire-pulse`; el monitor del sink da el **audio del sistema**.) Detección de encoder HW (VA-API) con fallback a `x264enc`.
- **Atajo global:** en Wayland las apps no pueden registrar atajos globales por sí mismas → la app expone comandos CLI/D-Bus (`mis-looms toggle`) y se enlaza en `~/.config/hypr/bindings.conf` (`bind = SUPER SHIFT, R, exec, mis-looms toggle`). También portal `GlobalShortcuts` donde exista.
- **Subida/miniatura/enlace:** igual que Mac; miniatura con GStreamer (`gdkpixbufsink`/`jpegenc` en t=1s); portapapeles vía GTK/`wl-copy`; notificación vía `libnotify`/portal.
- **Distribución:** binario + `.desktop`; paquete AUR/Flatpak opcional.

## Contrato compartido
Ambas apps implementan el mismo cliente HTTP contra la API (documentar en `docs/api.md`): crear → subir partes → completar → miniatura. Reintentos por parte, y si la app se cierra se puede reanudar (guardar `upload_id` + partes completadas en un JSON local) o abortar.

## Estructura del repositorio
```
mis-looms/
  server/   Laravel
  macos/    Proyecto Xcode (Swift)
  linux/    Cargo workspace (Rust)
  docs/     api.md, despliegue.md, s3-setup.md
```

## Fases / orden de implementación
**Primera parte (Linux):**
1. **App Linux — grabación local:** crear `linux/` (Cargo), portal ScreenCast con `ashpd` + `restore_token`, pipeline GStreamer (pantalla + mic + monitor) → MP4 en `~/Videos/mis-looms/`, comando `mis-looms toggle`, icono en bandeja con estado. Verificar con `ffprobe`.
2. **S3 + Laravel 13 API** (crear/firmar partes/completar/miniatura) + página pública `/v/{slug}` en Blade. Probar con `curl` + un archivo MP4 de la fase 1.
3. **App Linux — subida:** cliente multipart con progreso y reintentos, miniatura, enlace al portapapeles + notificación, configuración (URL + token en keyring).
4. **Panel admin en Blade** (listado, renombrar, borrar, generar token).

**Segunda parte:**
5. **App macOS** con el mismo contrato de API.
6. Mejoras: pausa, recortar inicio/fin, webcam, CloudFront, contraseña opcional por video, expiración de enlaces.

## Riesgos / consideraciones
- **Hosting compartido:** sin workers ni ffmpeg → todo procesamiento (miniatura, metadatos) se hace en el cliente. Verificar que el host permita llamadas salientes HTTPS (para la SDK de AWS) y PHP ≥ 8.2.
- **Wayland:** dependencia del portal; cada sesión el portal puede pedir elegir pantalla (se puede usar `persist_mode` del portal para recordar el permiso con `restore_token`).
- **Audio del sistema en Mac** requiere macOS 13+ (ScreenCaptureKit); antes requeriría drivers virtuales tipo BlackHole.
- **Costos S3:** egress público se paga por GB visto; CloudFront reduce esto.
- **Seguridad:** URLs públicas son "no listadas" (slug no adivinable, ULID); el bucket no debe permitir `ListBucket` público.

## Verificación
- Backend: tests Feature de Laravel (Pest) para la API con S3 mockeado (`Storage::fake` no cubre multipart → mock del `S3Client`); prueba real con `aws s3api` en bucket de staging.
- Linux: grabar 30 s con mic + audio de sistema, verificar con `ffprobe` (H.264 + AAC, `moov` al inicio), subir y abrir `/v/{slug}` en Chrome/Firefox/Safari móvil.
- Mac: mismo checklist; probar con permisos denegados y con red cortada a mitad de subida (reanudación).
- Panel: borrar un video y confirmar que el objeto desaparece de S3.
