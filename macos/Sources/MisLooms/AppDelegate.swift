import AppKit
import AVFoundation
import Carbon.HIToolbox
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let recorder = Recorder()
    private var item: NSStatusItem!
    private var atajoIniciar: AtajoGlobal?  // ⌥⇧L
    private var atajoFinalizar: AtajoGlobal?  // ⌘⇧L
    private var temporizador: Timer?
    private var inicio: Date?
    private var ocupado = false  // evita dobles clics mientras arranca o cierra

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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        actualizarInterfaz()
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
            boton.title = ""
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

        menu.addItem(.separator())

        let sistema = NSMenuItem(title: "Grabar audio del sistema", action: #selector(cambiarAudioSistema), keyEquivalent: "")
        sistema.target = self
        sistema.state = audioDelSistema ? .on : .off
        sistema.isEnabled = !recorder.grabando
        menu.addItem(sistema)

        let abrir = NSMenuItem(title: "Abrir carpeta de grabaciones", action: #selector(abrirCarpeta), keyEquivalent: "")
        abrir.target = self
        menu.addItem(abrir)

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

    @objc private func abrirCarpeta() {
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        NSWorkspace.shared.open(carpeta)
    }

    // MARK: - Avisos

    private func notificar(_ titulo: String, _ texto: String) {
        let contenido = UNMutableNotificationContent()
        contenido.title = titulo
        contenido.body = texto
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
