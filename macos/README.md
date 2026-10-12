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

## Estructura

- `Sources/MisLooms/Recorder.swift` — captura y escritura del MP4.
- `Sources/MisLooms/AppDelegate.swift` — icono de barra, menú, notificaciones.
- `Sources/MisLooms/AtajoGlobal.swift` — atajo global (Carbon, sin permiso de Accesibilidad).
