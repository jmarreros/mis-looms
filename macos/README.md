# Mis Looms — app de macOS

App de barra de menú en Swift (sin Xcode, solo Command Line Tools + SwiftPM).
Graba la pantalla principal completa + micrófono con ScreenCaptureKit y AVAssetWriter
a MP4 (H.264 8 Mbps máx. 1080p, AAC, faststart) en `~/Movies/mis-looms/`.

Requisitos: macOS 15+ (el micrófono se captura con ScreenCaptureKit) y Swift 5.9+.

## Compilar

```
cd macos
./crear-certificado.sh   # una sola vez: certificado de firma local "Mis Looms Dev"
./compilar.sh            # genera build/Mis Looms.app
open "build/Mis Looms.app"
```

Sin el certificado, `compilar.sh` firma ad-hoc y macOS vuelve a pedir los permisos en
cada compilación.

## Uso

- Icono en la barra de menú: iniciar/finalizar, abrir carpeta, audio del sistema.
- Atajos globales: **⌥⇧L** inicia la grabación y **⌘⇧L** la finaliza (cada uno solo actúa
  en su estado). Se definen en `AppDelegate.applicationDidFinishLaunching`.
- Permisos que pide la primera vez: Grabación de pantalla y Micrófono.
  Tras conceder Grabación de pantalla, macOS pide reabrir la app.
- Audio del sistema: **desactivado por defecto** (opción del menú). Si se activa, se
  escribe como segunda pista; pendiente mezclarla con el micrófono en una sola pista
  para que el `<video>` web la reproduzca (ver TODO en `Recorder.swift`).

## Subida al servidor (Fase 3)

1. En el menú: **Ajustes…** → pega la URL del servidor y el token (panel web › Token de la
   app) y pulsa "Probar conexión". El token se guarda en el Llavero de macOS.
2. Al finalizar una grabación, la app sube sola el MP4 directo a S3 (partes de 10 MB, 3 en
   paralelo, 4 reintentos por parte), sube una miniatura del segundo 1 y cierra la subida.
3. Copia el enlace `…/v/{slug}` al portapapeles y notifica; pulsar la notificación abre el video.
   El menú muestra el progreso (también junto al icono), **Cancelar subida** y **Copiar último enlace**.

Si la subida falla o la app se cierra a mitad, el estado queda en
`~/Library/Application Support/Mis Looms/subidas/` y se **reanuda al abrir la app** (solo
sube las partes que faltan) o desde **Reintentar subidas pendientes**. Si el servidor ya cerró
esa subida (caducó tras 24 h o se abortó), empieza de cero con el mismo archivo. Cancelarla
desde el menú la aborta en el servidor.

Sin interfaz (scripts y pruebas), el mismo subidor está en el binario:

```
MISLOOMS_URL=https://tu-dominio MISLOOMS_TOKEN=… "build/Mis Looms.app/Contents/MacOS/MisLooms" subir video.mp4
… MisLooms reanudar        # reanuda las pendientes · Ctrl+C cancela y aborta en el servidor
```
(`MISLOOMS_ESTADO` cambia la carpeta del estado de subidas.)

## Estructura

- `Sources/MisLooms/Recorder.swift` — captura y escritura del MP4.
- `Sources/MisLooms/AppDelegate.swift` — icono de barra, menú, notificaciones, cola de subidas.
- `Sources/MisLooms/Subidor.swift` — multipart a S3 con progreso, reintentos y estado en disco.
- `Sources/MisLooms/ClienteAPI.swift` — cliente de `docs/api.md`.
- `Sources/MisLooms/Configuracion.swift` — URL (UserDefaults) y token (Llavero).
- `Sources/MisLooms/Medios.swift` — metadatos y miniatura del MP4.
- `Sources/MisLooms/VentanaAjustes.swift` — ventana de URL + token.
- `Sources/MisLooms/LineaDeComandos.swift` — modo `subir` / `reanudar` sin interfaz.
- `Sources/MisLooms/AtajoGlobal.swift` — atajo global (Carbon, sin permiso de Accesibilidad).
