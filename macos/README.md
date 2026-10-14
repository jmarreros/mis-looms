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

- **Controles flotantes** (`PanelFlotante.swift`): una píldora siempre encima de las demás
  ventanas y en todos los escritorios (también sobre apps a pantalla completa). En reposo
  muestra «● Grabar» (y «Subiendo N %» si hay una subida) y una ✕ para salir de la app; grabando,
  el cronómetro en rojo con pausar y finalizar; en pausa, el cronómetro en amarillo con reanudar,
  descartar (papelera) y finalizar. Descartar pide un segundo clic en 4 s («¿Descartar? Pulsa de
  nuevo»), borra el MP4 a medias y no sube nada. Se arrastra
  desde cualquier parte, recuerda su posición (abajo a la izquierda por defecto) y responde al
  primer clic sin activar la app. No sale en el video: la captura excluye las ventanas de la
  propia app. Se oculta con **Mostrar controles flotantes** en el menú.
- **Cuenta regresiva** (`CuentaRegresiva.swift`): al pulsar «Grabar» sale un 3, 2, 1 grande en el
  centro de la pantalla (con un anillo que se vacía cada segundo) y «Empieza en N» en el panel,
  con una ✕ para cancelar (también cancela ⌥⇧L o el menú). La captura empieza al llegar a cero y
  la cuenta no sale en el video. Se desactiva en el menú: **Cuenta regresiva de 3 s**.
- **Pausa**: desde el panel o el menú. En pausa se descartan las muestras de ScreenCaptureKit y
  al reanudar se les resta el tiempo pausado, así que el MP4 sale continuo, sin huecos ni
  congelados; el cronómetro no cuenta las pausas.
- Icono en la barra de menú: iniciar/finalizar, pausar/reanudar, descartar (con confirmación),
  abrir carpeta, audio del sistema.
- Atajo global: **⌥⇧L** inicia la grabación y, pulsado de nuevo, la finaliza (el mismo atajo
  alterna). Se define en `AppDelegate.applicationDidFinishLaunching`.
- Permisos que pide la primera vez: Grabación de pantalla y Micrófono.
  Tras conceder Grabación de pantalla, macOS pide reabrir la app.
- Audio del sistema: **desactivado por defecto** (opción del menú). Si se activa, se
  escribe como segunda pista; pendiente mezclarla con el micrófono en una sola pista
  para que el `<video>` web la reproduzca (ver TODO en `Recorder.swift`).

## Subida al servidor (Fase 3)

1. En el menú: **Ajustes…** → pega la URL del servidor y el token (panel web › Token de la
   app) y pulsa "Probar conexión". El token se guarda en el Llavero de macOS.
2. Al finalizar una grabación, la barra muestra «Finalizando…» (se cierra el MP4) y luego
   «Subiendo N%», con una notificación «Subiendo al servidor». La app sube el MP4 directo a S3
   (partes de 10 MB, 3 en paralelo, 4 reintentos por parte), sube una miniatura del segundo 1
   y cierra la subida.
3. Al terminar copia el enlace `…/v/{slug}` al portapapeles, notifica y **abre el video en el
   navegador**. Se desactiva en el menú (**Abrir el enlace al terminar**); solo abre el
   navegador con las grabaciones de la sesión actual, no con subidas retomadas al abrir la app.
   El menú muestra el progreso, **Cancelar subida** y **Copiar último enlace**.

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
