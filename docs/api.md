# API para las apps nativas

Base: `https://TU-DOMINIO/api`. Todas las rutas exigen `Authorization: Bearer <token>`
(token personal de Sanctum, se genera en el panel › "Token de la app") y
`Accept: application/json`. Mismo contrato para las apps de macOS y Linux.

## Flujo

1. `POST /api/videos` → devuelve `slug`, `share_url`, `upload_id` y una URL prefirmada por parte.
2. `PUT` de cada parte **directo a S3** (sin `Authorization`, sin cabeceras extra). Guardar el
   encabezado `ETag` de cada respuesta.
3. (Opcional) `POST /api/videos/{slug}/thumbnail` → `PUT` del JPG a la URL devuelta.
4. `POST /api/videos/{slug}/complete` con las partes y sus ETags → el video queda `ready`.
5. Copiar `video.share_url` al portapapeles y notificar.

## Endpoints

### `POST /api/videos`
```json
{ "size": 3115865, "title": "opcional", "duration": 12.7, "width": 1670, "height": 1080 }
```
`size` (bytes del MP4) es obligatorio: define el número de partes (`ceil(size / part_size)`).
Respuesta `201`:
```json
{
  "video": { "slug": "daxp1kui7eny", "status": "uploading",
             "share_url": "https://dominio/v/daxp1kui7eny", "video_url": "https://…/videos/daxp1kui7eny.mp4", "…": "…" },
  "upload_id": "…",
  "part_size": 10485760,
  "parts": [ { "part_number": 1, "url": "https://…s3…?X-Amz-Signature=…" } ]
}
```
Cada parte, salvo la última, mide exactamente `part_size` (10 MB). La última lleva el resto.
Las URLs caducan a los 60 minutos.

### `POST /api/videos/{slug}/parts`
`{ "parts": [3, 5] }` → `{ "parts": [ { "part_number": 3, "url": "…" }, … ] }`.
Vuelve a firmar partes (URLs caducadas o subida reanudada).

### `POST /api/videos/{slug}/thumbnail`
→ `{ "upload_url": "…", "headers": { "Content-Type": "image/jpeg" } }`.
El `PUT` debe enviar exactamente ese `Content-Type`.

### `POST /api/videos/{slug}/complete`
```json
{ "parts": [ { "part_number": 1, "etag": "\"abc…\"" } ],
  "duration": 12.7, "width": 1670, "height": 1080, "has_thumbnail": true }
```
El `etag` se envía tal cual lo devuelve S3 (con comillas). Pon `has_thumbnail: true` solo si ya
subiste la miniatura. Respuesta `200` con `video` (`status: "ready"`). Si S3 rechaza la unión
responde `502` y la subida sigue abierta para corregir y reintentar.

### `POST /api/videos/{slug}/abort`
Cancela la subida y marca el video `failed`.

## Errores
- `401` token ausente o inválido · `404` slug inexistente · `422` validación.
- `409` la subida ya no está en curso (ya completada, abortada o caducada).
- Una subida sin completar en 24 h se marca `failed` sola (cron `mislooms:limpiar-subidas`).

## Reanudar
Guardar localmente `slug`, `upload_id` y las partes ya subidas (con su ETag). Si la app se cierra,
pedir `/parts` para las que faltan, subirlas y llamar a `/complete`; o `/abort`.
