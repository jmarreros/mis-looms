import AppKit

if LineaDeComandos.ejecutarSiCorresponde() {
    dispatchMain()  // la tarea de la línea de comandos termina el proceso con exit()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegado = AppDelegate()
    app.delegate = delegado
    app.setActivationPolicy(.accessory)  // solo barra de menú, sin icono en el Dock
    app.run()
}
