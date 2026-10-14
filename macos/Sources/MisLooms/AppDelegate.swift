import AppKit
import AVFoundation
import Carbon.HIToolbox
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let recorder = Recorder()
    private var item: NSStatusItem!
    private var atajo: AtajoGlobal?  // ⌥⇧L: inicia o finaliza la grabación según el estado
    private var temporizador: Timer?
    private var inicio: Date?  // inicio del tramo actual; nil en pausa
    private var acumulado: TimeInterval = 0  // segundos grabados en tramos anteriores a la última pausa
    private var ocupado = false  // evita dobles clics mientras arranca o cierra

    private let ajustes = VentanaAjustes()
    private let panel = PanelFlotante()
    private let cuenta = CuentaRegresiva()
    private var arranque: Task<Void, Never>?  // de pulsar «Grabar» a tener la captura en marcha
    private var faltan: Int?  // segundos de la cuenta regresiva en curso
    private var subida: Task<Void, Never>?  // subidas pendientes, una detrás de otra
    private var progresoSubida: Int?  // 0–100 mientras se sube
    private var fallidas: Set<String> = []  // fallaron en esta sesión: no se reintentan solas
    private var ultimoEnlace: String?
    private var finalizando = false  // entre pulsar "finalizar" y tener el MP4 cerrado
    private var abrirTrasSubir: Set<String> = []  // grabaciones de esta sesión: al subirse abren el navegador

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
    private static let claveAbrirEnlace = "abrirEnlaceAlTerminar"  // true por defecto
    private static let claveMostrarPanel = "mostrarPanelFlotante"  // true por defecto
    private static let claveCuentaRegresiva = "cuentaRegresiva"  // true por defecto
    private static let segundosCuenta = 3

    private var conCuentaRegresiva: Bool {
        get { UserDefaults.standard.object(forKey: Self.claveCuentaRegresiva) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.claveCuentaRegresiva) }
    }

    private var mostrarPanel: Bool {
        get { UserDefaults.standard.object(forKey: Self.claveMostrarPanel) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.claveMostrarPanel) }
    }

    private var abrirEnlace: Bool {
        get { UserDefaults.standard.object(forKey: Self.claveAbrirEnlace) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.claveAbrirEnlace) }
    }

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
        atajo = AtajoGlobal(tecla: kVK_ANSI_L, modificadores: optionKey | shiftKey) { [weak self] in
            self?.alternarGrabacion()
        }
        recorder.alDetenerseConError = { [weak self] error in
            Task { @MainActor in self?.capturaInterrumpida(error) }
        }
        NSApp.mainMenu = Self.menuPrincipal()
        ajustes.alGuardar = { [weak self] in self?.reintentarSubidas() }
        panel.alGrabar = { [weak self] in self?.alternarGrabacion() }
        panel.alFinalizar = { [weak self] in self?.alternarGrabacion() }
        panel.alPausar = { [weak self] in self?.pausar() }
        panel.alReanudar = { [weak self] in self?.reanudar() }
        panel.alDescartar = { [weak self] in self?.descartar() }
        panel.alSalir = { NSApp.terminate(nil) }
        panel.alCancelarCuenta = { [weak self] in self?.cancelarCuenta() }
        if mostrarPanel { panel.mostrar() }
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

    /// Atajo y menú: inicia la grabación si no hay una en curso y la finaliza si la hay.
    private func alternarGrabacion() {
        if faltan != nil { cancelarCuenta(); return }  // durante la cuenta, el mismo gesto la cancela
        guard !ocupado, !finalizando else { return }
        if recorder.grabando { detener() } else { iniciar() }
    }

    private func iniciar() {
        ocupado = true
        actualizarInterfaz()
        arranque = Task {
            defer {
                ocupado = false
                arranque = nil
                actualizarInterfaz()
            }
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                avisarPermiso("Micrófono")
                return
            }
            if conCuentaRegresiva, !(await contarHastaCero()) { return }
            do {
                try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
                let formato = DateFormatter()
                formato.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let destino = carpeta.appendingPathComponent("looms-\(formato.string(from: Date())).mp4")
                try await recorder.iniciar(destino: destino, audioDelSistema: audioDelSistema)
                inicio = Date()
                acumulado = 0
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

    /// 3, 2, 1 en pantalla y en el panel. Devuelve false si se canceló.
    private func contarHastaCero() async -> Bool {
        defer {
            faltan = nil
            cuenta.ocultar()
            actualizarInterfaz()
        }
        for n in stride(from: Self.segundosCuenta, through: 1, by: -1) {
            faltan = n
            cuenta.mostrar(n)
            actualizarInterfaz()
            do { try await Task.sleep(for: .seconds(1)) } catch { return false }
        }
        return true
    }

    private func cancelarCuenta() {
        guard faltan != nil else { return }
        arranque?.cancel()
    }

    private func pausar() {
        guard recorder.grabando, !recorder.pausado, !ocupado, !finalizando else { return }
        recorder.pausar()
        acumulado += Date().timeIntervalSince(inicio ?? Date())
        inicio = nil
        actualizarInterfaz()
    }

    private func reanudar() {
        guard recorder.grabando, recorder.pausado, !ocupado, !finalizando else { return }
        recorder.reanudar()
        inicio = Date()
        actualizarInterfaz()
    }

    /// Tira la grabación en pausa (sin subirla) y deja la app lista para empezar otra.
    private func descartar() {
        guard recorder.grabando, recorder.pausado, !ocupado, !finalizando else { return }
        ocupado = true
        temporizador?.invalidate()
        temporizador = nil
        inicio = nil
        acumulado = 0
        actualizarInterfaz()
        Task {
            await recorder.descartar()
            ocupado = false
            actualizarInterfaz()
        }
    }

    /// Segundos grabados sin contar las pausas.
    private var segundosGrabados: Int {
        Int(acumulado + (inicio.map { Date().timeIntervalSince($0) } ?? 0))
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
        acumulado = 0
        finalizando = true
        actualizarInterfaz()
        defer {
            finalizando = false
            actualizarInterfaz()
        }
        do {
            let url = try await recorder.detener()
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
        let transcurrido = segundosGrabados
        if finalizando {
            boton.image = Self.iconoReposo
            boton.title = " Finalizando…"
            panel.actualizar(.finalizando)
        } else if recorder.grabando {
            let pausado = recorder.pausado
            boton.image = NSImage(systemSymbolName: pausado ? "pause.circle.fill" : "record.circle.fill",
                                  accessibilityDescription: pausado ? "En pausa" : "Grabando")?
                .withSymbolConfiguration(.init(paletteColors: [pausado ? .systemYellow : .systemRed]))
            boton.title = String(format: " %d:%02d", transcurrido / 60, transcurrido % 60)
            panel.actualizar(pausado ? .pausado(segundos: transcurrido) : .grabando(segundos: transcurrido))
        } else {
            boton.image = Self.iconoReposo
            boton.title = progresoSubida.map { " Subiendo \($0)%" } ?? ""
            if let faltan {
                boton.title = " Empieza en \(faltan)"
                panel.actualizar(.cuentaRegresiva(faltan))
            } else {
                panel.actualizar(ocupado ? .iniciando : .reposo(subida: progresoSubida))
            }
        }
        item.menu = construirMenu()
    }

    private func construirMenu() -> NSMenu {
        let menu = NSMenu()

        let titulo = faltan != nil ? "Cancelar cuenta regresiva"
            : finalizando ? "Finalizando grabación…" : recorder.grabando ? "Finalizar grabación" : "Iniciar grabación"
        let alternar = NSMenuItem(title: titulo, action: #selector(alternarDesdeMenu), keyEquivalent: "l")
        alternar.keyEquivalentModifierMask = [.option, .shift]
        alternar.target = self
        alternar.isEnabled = faltan != nil || (!ocupado && !finalizando)
        menu.addItem(alternar)

        if recorder.grabando {
            let pausa = NSMenuItem(title: recorder.pausado ? "Reanudar grabación" : "Pausar grabación",
                                   action: #selector(alternarPausa), keyEquivalent: "")
            pausa.target = self
            pausa.isEnabled = !ocupado && !finalizando
            menu.addItem(pausa)

            let descartar = NSMenuItem(title: "Descartar grabación", action: #selector(descartarDesdeMenu), keyEquivalent: "")
            descartar.target = self
            descartar.isEnabled = recorder.pausado && !ocupado && !finalizando
            menu.addItem(descartar)
        }

        if let progreso = progresoSubida {
            menu.addItem(.separator())
            let estado = NSMenuItem(title: "Subiendo al servidor… \(progreso) %", action: nil, keyEquivalent: "")
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

        let cuentaAtras = NSMenuItem(title: "Cuenta regresiva de \(Self.segundosCuenta) s", action: #selector(cambiarCuentaRegresiva), keyEquivalent: "")
        cuentaAtras.target = self
        cuentaAtras.state = conCuentaRegresiva ? .on : .off
        menu.addItem(cuentaAtras)

        let abrirNavegador = NSMenuItem(title: "Abrir el enlace al terminar", action: #selector(cambiarAbrirEnlace), keyEquivalent: "")
        abrirNavegador.target = self
        abrirNavegador.state = abrirEnlace ? .on : .off
        menu.addItem(abrirNavegador)

        let flotante = NSMenuItem(title: "Mostrar controles flotantes", action: #selector(cambiarMostrarPanel), keyEquivalent: "")
        flotante.target = self
        flotante.state = mostrarPanel ? .on : .off
        menu.addItem(flotante)

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

    @objc private func alternarDesdeMenu() { alternarGrabacion() }

    /// Desde el menú pide confirmación: borra la grabación sin posibilidad de recuperarla.
    @objc private func descartarDesdeMenu() {
        let alerta = NSAlert()
        alerta.messageText = "¿Descartar la grabación?"
        alerta.informativeText = "Se borrará lo grabado hasta ahora y no se subirá."
        alerta.addButton(withTitle: "Descartar")
        alerta.addButton(withTitle: "Cancelar")
        alerta.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        if alerta.runModal() == .alertFirstButtonReturn { descartar() }
    }

    @objc private func alternarPausa() {
        if recorder.pausado { reanudar() } else { pausar() }
    }

    @objc private func cambiarMostrarPanel() {
        mostrarPanel.toggle()
        if mostrarPanel { panel.mostrar() } else { panel.ocultar() }
        actualizarInterfaz()
    }

    @objc private func cambiarAudioSistema() {
        audioDelSistema.toggle()
        actualizarInterfaz()
    }

    @objc private func cambiarCuentaRegresiva() {
        conCuentaRegresiva.toggle()
        actualizarInterfaz()
    }

    @objc private func cambiarAbrirEnlace() {
        abrirEnlace.toggle()
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
            abrirTrasSubir.insert(try EstadoSubida.nueva(archivo: archivo).id)
        } catch {
            notificar("No se pudo preparar la subida", error.localizedDescription)
            return
        }
        guard Configuracion.completa else {
            notificar("Grabación guardada", "Falta configurar el servidor: abre Ajustes en el menú y se subirá al guardar la URL y el token.")
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
        let nombre = (estado.archivo as NSString).lastPathComponent
        let tamano = ByteCountFormatter.string(fromByteCount: Int64(estado.tamano), countStyle: .file)
        notificar(estado.slug == nil ? "Subiendo al servidor" : "Retomando la subida", "\(nombre) · \(tamano)")
        do {
            let subidor = Subidor(api: try ClienteAPI())
            let enlace = try await subidor.procesar(estado) { [weak self] fraccion in
                Task { @MainActor in self?.actualizarProgreso(fraccion) }
            }
            ultimoEnlace = enlace
            copiar(enlace)
            notificar("Enlace copiado", enlace, url: enlace)
            // Solo las grabaciones de esta sesión abren el navegador; una subida retomada al
            // arrancar la app no debe abrir ventanas por sorpresa.
            if abrirTrasSubir.remove(estado.id) != nil, abrirEnlace, let url = URL(string: enlace) {
                NSWorkspace.shared.open(url)
            }
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
