import AppKit
import AVFoundation
import Carbon.HIToolbox
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let recorder = Recorder()
    private var item: NSStatusItem!
    private var atajoIniciar: AtajoGlobal?  // ⌥⇧L
    private var atajoFinalizar: AtajoGlobal?  // ⌘⇧L
    private var temporizador: Timer?
    private var inicio: Date?
    private var ocupado = false  // evita dobles clics mientras arranca o cierra

    private let ajustes = VentanaAjustes()
    private var subida: Task<Void, Never>?  // subidas pendientes, una detrás de otra
    private var progresoSubida: Int?  // 0–100 mientras se sube
    private var fallidas: Set<String> = []  // fallaron en esta sesión: no se reintentan solas
    private var ultimoEnlace: String?

    /// Logo monocromo (marca/logo-mono.svg, copiado por compilar.sh) como imagen plantilla:
    /// macOS lo tiñe según el tema. Fuera del .app (swift run) se usa un símbolo del sistema.
    private static let iconoReposo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "barra-menu", withExtension: "svg"),
              let imagen = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Mis Looms")
        }
        imagen.size = NSSize(width: 18, height: 18)
        imagen.isTemplate = true
        imagen.accessibilityDescription = "Mis Looms"
        return imagen
    }()

    private static let claveAudioSistema = "grabarAudioDelSistema"  // false por defecto

    private var audioDelSistema: Bool {
        get { UserDefaults.standard.bool(forKey: Self.claveAudioSistema) }
        set { UserDefaults.standard.set(newValue, forKey: Self.claveAudioSistema) }
    }

    private var carpeta: URL {
        FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mis-looms", isDirectory: true)
    }

    // MARK: - Ciclo de vida

    func applicationDidFinishLaunching(_ notificacion: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        atajoIniciar = AtajoGlobal(tecla: kVK_ANSI_L, modificadores: optionKey | shiftKey) { [weak self] in
            guard let self, !self.recorder.grabando, !self.ocupado else { return }
            self.iniciar()
        }
        atajoFinalizar = AtajoGlobal(tecla: kVK_ANSI_L, modificadores: cmdKey | shiftKey) { [weak self] in
            guard let self, self.recorder.grabando, !self.ocupado else { return }
            self.detener()
        }
        recorder.alDetenerseConError = { [weak self] error in
            Task { @MainActor in self?.capturaInterrumpida(error) }
        }
        NSApp.mainMenu = Self.menuPrincipal()
        ajustes.alGuardar = { [weak self] in self?.reintentarSubidas() }
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        actualizarInterfaz()
        procesarPendientes()  // retoma lo que quedó a medias en la sesión anterior
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.grabando else { return .terminateNow }
        Task {
            _ = try? await recorder.detener()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - Acciones

    private func iniciar() {
        ocupado = true
        actualizarInterfaz()
        Task {
            defer { ocupado = false; actualizarInterfaz() }
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                avisarPermiso("Micrófono")
                return
            }
            do {
                try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
                let formato = DateFormatter()
                formato.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let destino = carpeta.appendingPathComponent("looms-\(formato.string(from: Date())).mp4")
                try await recorder.iniciar(destino: destino, audioDelSistema: audioDelSistema)
                inicio = Date()
                temporizador = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.actualizarInterfaz() }
                }
            } catch {
                // Sin permiso de Grabación de pantalla, ScreenCaptureKit lanza un error aquí.
                if !CGPreflightScreenCaptureAccess() {
                    avisarPermiso("Grabación de pantalla")
                } else {
                    notificar("No se pudo iniciar la grabación", error.localizedDescription)
                }
            }
        }
    }

    private func detener() {
        ocupado = true
        actualizarInterfaz()
        Task {
            defer { ocupado = false; actualizarInterfaz() }
            await terminarYNotificar()
        }
    }

    private func terminarYNotificar() async {
        temporizador?.invalidate()
        temporizador = nil
        inicio = nil
        do {
            let url = try await recorder.detener()
            notificar("Grabación guardada", url.lastPathComponent)
            encolarSubida(url)
        } catch {
            notificar("Error al guardar la grabación", error.localizedDescription)
        }
    }

    private func capturaInterrumpida(_ error: Error) {
        Task {
            await terminarYNotificar()
            notificar("La captura se detuvo", error.localizedDescription)
            actualizarInterfaz()
        }
    }

    // MARK: - Interfaz

    private func actualizarInterfaz() {
        guard let boton = item.button else { return }
        if recorder.grabando {
            let transcurrido = Int(Date().timeIntervalSince(inicio ?? Date()))
            boton.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Grabando")?
                .withSymbolConfiguration(.init(paletteColors: [.systemRed]))
            boton.title = String(format: " %d:%02d", transcurrido / 60, transcurrido % 60)
        } else {
            boton.image = Self.iconoReposo
            boton.title = progresoSubida.map { " \($0)%" } ?? ""
        }
        item.menu = construirMenu()
    }

    private func construirMenu() -> NSMenu {
        let menu = NSMenu()

        let iniciar = NSMenuItem(title: "Iniciar grabación", action: #selector(iniciarDesdeMenu), keyEquivalent: "l")
        iniciar.keyEquivalentModifierMask = [.option, .shift]
        iniciar.target = self
        iniciar.isEnabled = !recorder.grabando && !ocupado
        menu.addItem(iniciar)

        let finalizar = NSMenuItem(title: "Finalizar grabación", action: #selector(finalizarDesdeMenu), keyEquivalent: "l")
        finalizar.keyEquivalentModifierMask = [.command, .shift]
        finalizar.target = self
        finalizar.isEnabled = recorder.grabando && !ocupado
        menu.addItem(finalizar)

        if let progreso = progresoSubida {
            menu.addItem(.separator())
            let estado = NSMenuItem(title: "Subiendo… \(progreso) %", action: nil, keyEquivalent: "")
            estado.isEnabled = false
            menu.addItem(estado)
            let cancelar = NSMenuItem(title: "Cancelar subida", action: #selector(cancelarSubida), keyEquivalent: "")
            cancelar.target = self
            menu.addItem(cancelar)
        } else if EstadoSubida.hayPendientes {
            menu.addItem(.separator())
            let reintentar = NSMenuItem(title: "Reintentar subidas pendientes", action: #selector(reintentarSubidas), keyEquivalent: "")
            reintentar.target = self
            menu.addItem(reintentar)
        }

        menu.addItem(.separator())

        let sistema = NSMenuItem(title: "Grabar audio del sistema", action: #selector(cambiarAudioSistema), keyEquivalent: "")
        sistema.target = self
        sistema.state = audioDelSistema ? .on : .off
        sistema.isEnabled = !recorder.grabando
        menu.addItem(sistema)

        let abrir = NSMenuItem(title: "Abrir carpeta de grabaciones", action: #selector(abrirCarpeta), keyEquivalent: "")
        abrir.target = self
        menu.addItem(abrir)

        let copiar = NSMenuItem(title: "Copiar último enlace", action: #selector(copiarUltimoEnlace), keyEquivalent: "")
        copiar.target = self
        copiar.isEnabled = ultimoEnlace != nil
        menu.addItem(copiar)

        menu.addItem(.separator())

        let preferencias = NSMenuItem(title: "Ajustes…", action: #selector(abrirAjustes), keyEquivalent: ",")
        preferencias.target = self
        menu.addItem(preferencias)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de Mis Looms", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func iniciarDesdeMenu() { iniciar() }
    @objc private func finalizarDesdeMenu() { detener() }

    @objc private func cambiarAudioSistema() {
        audioDelSistema.toggle()
        actualizarInterfaz()
    }

    @objc private func abrirAjustes() { ajustes.mostrar() }

    @objc private func copiarUltimoEnlace() {
        if let enlace = ultimoEnlace { copiar(enlace) }
    }

    @objc private func cancelarSubida() { subida?.cancel() }

    @objc private func reintentarSubidas() {
        fallidas.removeAll()
        procesarPendientes()
    }

    @objc private func abrirCarpeta() {
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        NSWorkspace.shared.open(carpeta)
    }

    // MARK: - Subida

    /// Guarda la grabación como subida pendiente y la procesa (o avisa de que falta configurar).
    private func encolarSubida(_ archivo: URL) {
        do {
            _ = try EstadoSubida.nueva(archivo: archivo)
        } catch {
            notificar("No se pudo preparar la subida", error.localizedDescription)
            return
        }
        guard Configuracion.completa else {
            notificar("Falta configurar el servidor", "Abre Ajustes en el menú: la grabación se subirá al guardar la URL y el token.")
            return
        }
        procesarPendientes()
    }

    private func procesarPendientes() {
        guard subida == nil, Configuracion.completa else { return }
        subida = Task {
            defer {
                subida = nil
                progresoSubida = nil
                actualizarInterfaz()
            }
            while let estado = EstadoSubida.pendientes().first(where: { !fallidas.contains($0.id) }) {
                if await !subir(estado) { break }
            }
        }
    }

    /// Devuelve false si el usuario canceló (se detiene la cola).
    private func subir(_ estado: EstadoSubida) async -> Bool {
        progresoSubida = 0
        actualizarInterfaz()
        do {
            let subidor = Subidor(api: try ClienteAPI())
            let enlace = try await subidor.procesar(estado) { [weak self] fraccion in
                Task { @MainActor in self?.actualizarProgreso(fraccion) }
            }
            ultimoEnlace = enlace
            copiar(enlace)
            notificar("Enlace copiado", enlace, url: enlace)
            return true
        } catch is CancellationError {
            notificar("Subida cancelada", "El video sigue en la carpeta de grabaciones.")
            return false
        } catch {
            fallidas.insert(estado.id)
            notificar("No se pudo subir el video", "\(error.localizedDescription) Puedes reintentarlo desde el menú.")
            return true
        }
    }

    private func actualizarProgreso(_ fraccion: Double) {
        let porcentaje = Int(fraccion * 100)
        guard subida != nil, porcentaje != progresoSubida else { return }
        progresoSubida = porcentaje
        actualizarInterfaz()
    }

    private func copiar(_ texto: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(texto, forType: .string)
    }

    // MARK: - Avisos

    /// Una app de barra de menú no tiene menú principal: sin un menú Edición, ⌘V/⌘C/⌘X no
    /// funcionarían en los campos de la ventana de Ajustes.
    private static func menuPrincipal() -> NSMenu {
        let principal = NSMenu()
        let itemApp = NSMenuItem()
        let menuApp = NSMenu()
        menuApp.addItem(withTitle: "Salir de Mis Looms", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        itemApp.submenu = menuApp
        principal.addItem(itemApp)

        let itemEdicion = NSMenuItem()
        let edicion = NSMenu(title: "Edición")
        edicion.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        let rehacer = edicion.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "z")
        rehacer.keyEquivalentModifierMask = [.command, .shift]
        edicion.addItem(.separator())
        edicion.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edicion.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edicion.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edicion.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        itemEdicion.submenu = edicion
        principal.addItem(itemEdicion)
        return principal
    }

    nonisolated func userNotificationCenter(_ centro: UNUserNotificationCenter,
                                            willPresent notificacion: UNNotification,
                                            withCompletionHandler terminar: @escaping (UNNotificationPresentationOptions) -> Void) {
        terminar([.banner, .sound])
    }

    /// Pulsar la notificación "Enlace copiado" abre el video en el navegador.
    nonisolated func userNotificationCenter(_ centro: UNUserNotificationCenter,
                                            didReceive respuesta: UNNotificationResponse,
                                            withCompletionHandler terminar: @escaping () -> Void) {
        if let texto = respuesta.notification.request.content.userInfo["url"] as? String, let url = URL(string: texto) {
            Task { @MainActor in NSWorkspace.shared.open(url) }
        }
        terminar()
    }

    private func notificar(_ titulo: String, _ texto: String, url: String? = nil) {
        let contenido = UNMutableNotificationContent()
        contenido.title = titulo
        contenido.body = texto
        if let url { contenido.userInfo = ["url": url] }
        let peticion = UNNotificationRequest(identifier: UUID().uuidString, content: contenido, trigger: nil)
        UNUserNotificationCenter.current().add(peticion)
    }

    private func avisarPermiso(_ permiso: String) {
        let alerta = NSAlert()
        alerta.messageText = "Falta el permiso de \(permiso)"
        alerta.informativeText = "Concédelo en Ajustes del Sistema › Privacidad y seguridad › \(permiso) y vuelve a intentarlo."
        alerta.addButton(withTitle: "Abrir Ajustes")
        alerta.addButton(withTitle: "Cancelar")
        NSApp.activate(ignoringOtherApps: true)
        if alerta.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
