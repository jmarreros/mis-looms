import AppKit

/// Lo que muestra el panel flotante.
enum EstadoPanel: Equatable {
    case reposo(subida: Int?)  // listo para grabar; con el % si hay una subida en curso
    case iniciando
    case grabando(segundos: Int)
    case pausado(segundos: Int)
    case finalizando
}

/// Píldora siempre visible encima de las demás ventanas (y en todos los escritorios) con el
/// estado de la grabación y los botones grabar / pausar / reanudar / descartar / finalizar /
/// salir. No activa la
/// app al pulsarla, se arrastra desde cualquier parte y recuerda su posición. No sale en el
/// video: el grabador excluye las ventanas de la propia app.
@MainActor
final class PanelFlotante {
    var alGrabar: (() -> Void)?
    var alPausar: (() -> Void)?
    var alReanudar: (() -> Void)?
    var alFinalizar: (() -> Void)?
    var alDescartar: (() -> Void)?
    var alSalir: (() -> Void)?

    private static let alto: CGFloat = 44
    private static let margen: CGFloat = 24
    private static let esperaConfirmacion: TimeInterval = 4
    private static let nombreGuardado = "PanelFlotante"

    private static let fondo = NSColor(srgbRed: 0x1c / 255, green: 0x1a / 255, blue: 0x17 / 255, alpha: 0.94)
    private static let acento = NSColor(srgbRed: 0xd6 / 255, green: 0x7f / 255, blue: 0x48 / 255, alpha: 1)
    private static let texto = NSColor(white: 0.93, alpha: 1)
    private static let apagado = NSColor(white: 0.62, alpha: 1)

    private let panel: NSPanel
    private let pila = NSStackView()
    private let indicador = NSImageView()
    private let etiqueta = Etiqueta(labelWithString: "")
    private let botonGrabar: BotonPildora
    private let botonPausa: BotonRedondo
    private let botonFinalizar: BotonRedondo
    private let botonDescartar: BotonRedondo
    private let botonSalir: BotonRedondo
    private var estado: EstadoPanel?
    /// Descartar borra la grabación: el primer clic pide confirmación y el segundo descarta.
    private var confirmandoDescarte = false
    private var temporizadorConfirmacion: Timer?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: Self.alto),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)

        botonGrabar = BotonPildora(titulo: "Grabar")
        botonPausa = BotonRedondo(simbolo: "pause.fill", descripcion: "Pausar")
        botonFinalizar = BotonRedondo(simbolo: "stop.fill", descripcion: "Finalizar", color: .systemRed)
        botonDescartar = BotonRedondo(simbolo: "trash", descripcion: "Descartar y empezar de nuevo")
        botonSalir = BotonRedondo(simbolo: "xmark", descripcion: "Salir de Mis Looms", color: Self.apagado)

        let contenido = Fondo()
        contenido.wantsLayer = true
        contenido.layer?.backgroundColor = Self.fondo.cgColor
        contenido.layer?.cornerRadius = Self.alto / 2
        contenido.layer?.borderWidth = 1
        contenido.layer?.borderColor = NSColor(white: 1, alpha: 0.1).cgColor
        panel.contentView = contenido

        indicador.imageScaling = .scaleProportionallyDown
        etiqueta.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        etiqueta.textColor = Self.texto

        botonGrabar.target = self
        botonGrabar.action = #selector(pulsarGrabar)
        botonPausa.target = self
        botonPausa.action = #selector(pulsarPausa)
        botonFinalizar.target = self
        botonFinalizar.action = #selector(pulsarFinalizar)
        botonDescartar.target = self
        botonDescartar.action = #selector(pulsarDescartar)
        botonSalir.target = self
        botonSalir.action = #selector(pulsarSalir)

        pila.orientation = .horizontal
        pila.alignment = .centerY
        pila.spacing = 10
        pila.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 6)
        pila.translatesAutoresizingMaskIntoConstraints = false
        for vista in [indicador, etiqueta, botonGrabar, botonSalir, botonPausa, botonDescartar, botonFinalizar] as [NSView] {
            pila.addArrangedSubview(vista)
        }
        pila.setCustomSpacing(14, after: etiqueta)
        pila.setCustomSpacing(6, after: botonGrabar)
        pila.setCustomSpacing(6, after: botonPausa)
        pila.setCustomSpacing(6, after: botonDescartar)
        contenido.addSubview(pila)
        NSLayoutConstraint.activate([
            pila.leadingAnchor.constraint(equalTo: contenido.leadingAnchor),
            pila.trailingAnchor.constraint(equalTo: contenido.trailingAnchor),
            pila.topAnchor.constraint(equalTo: contenido.topAnchor),
            pila.bottomAnchor.constraint(equalTo: contenido.bottomAnchor),
            indicador.widthAnchor.constraint(equalToConstant: 16),
            indicador.heightAnchor.constraint(equalToConstant: 16),
        ])

        actualizar(.reposo(subida: nil))
        if !panel.setFrameUsingName(Self.nombreGuardado) || !visibleEnAlgunaPantalla() {
            colocarPorDefecto()
        }
        panel.setFrameAutosaveName(Self.nombreGuardado)
    }

    func mostrar() { panel.orderFrontRegardless() }
    func ocultar() { panel.orderOut(nil) }

    func actualizar(_ nuevo: EstadoPanel) {
        guard nuevo != estado else { return }
        if case .pausado = nuevo {} else { cancelarConfirmacion() }
        estado = nuevo
        pintar()
    }

    private func pintar() {
        guard let estado else { return }
        botonGrabar.isHidden = true
        botonSalir.isHidden = true
        botonPausa.isHidden = true
        botonDescartar.isHidden = true
        botonFinalizar.isHidden = true
        botonDescartar.resaltar(false)
        etiqueta.textColor = Self.texto

        switch estado {
        case .reposo(let subida):
            botonGrabar.isHidden = false
            botonSalir.isHidden = false
            if let subida {
                indicador.image = Self.simbolo("arrow.up.circle", Self.acento)
                etiqueta.stringValue = "Subiendo \(subida) %"
            } else {
                indicador.image = Self.simbolo("record.circle", Self.apagado)
                etiqueta.stringValue = "Mis Looms"
                etiqueta.textColor = Self.apagado
            }
        case .iniciando:
            indicador.image = Self.simbolo("hourglass", Self.acento)
            etiqueta.stringValue = "Preparando…"
        case .grabando(let segundos):
            indicador.image = Self.simbolo("circle.fill", .systemRed)
            etiqueta.stringValue = Self.reloj(segundos)
            botonPausa.cambiar(simbolo: "pause.fill", descripcion: "Pausar")
            botonPausa.isHidden = false
            botonFinalizar.isHidden = false
        case .pausado(let segundos):
            if confirmandoDescarte {
                indicador.image = Self.simbolo("trash.fill", .systemRed)
                etiqueta.stringValue = "¿Descartar? Pulsa de nuevo"
                etiqueta.textColor = .systemRed
                botonDescartar.resaltar(true)
            } else {
                indicador.image = Self.simbolo("pause.fill", .systemYellow)
                etiqueta.stringValue = "\(Self.reloj(segundos))  En pausa"
                etiqueta.textColor = .systemYellow
            }
            botonPausa.cambiar(simbolo: "play.fill", descripcion: "Reanudar")
            botonPausa.isHidden = false
            botonDescartar.isHidden = false
            botonFinalizar.isHidden = false
        case .finalizando:
            indicador.image = Self.simbolo("hourglass", Self.acento)
            etiqueta.stringValue = "Finalizando…"
        }
        ajustarTamano()
    }

    // MARK: - Acciones

    @objc private func pulsarGrabar() { alGrabar?() }
    @objc private func pulsarSalir() { alSalir?() }

    @objc private func pulsarFinalizar() {
        cancelarConfirmacion()
        alFinalizar?()
    }

    @objc private func pulsarPausa() {
        cancelarConfirmacion()
        if case .pausado = estado { alReanudar?() } else { alPausar?() }
    }

    @objc private func pulsarDescartar() {
        if confirmandoDescarte {
            cancelarConfirmacion()
            alDescartar?()
            return
        }
        confirmandoDescarte = true
        pintar()
        // Sin el segundo clic, la confirmación caduca sola.
        temporizadorConfirmacion = Timer.scheduledTimer(withTimeInterval: Self.esperaConfirmacion, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.cancelarConfirmacion()
                self?.pintar()
            }
        }
    }

    private func cancelarConfirmacion() {
        temporizadorConfirmacion?.invalidate()
        temporizadorConfirmacion = nil
        confirmandoDescarte = false
    }

    // MARK: - Tamaño y posición

    /// Cambia el ancho según el contenido sin mover el borde izquierdo.
    private func ajustarTamano() {
        pila.layoutSubtreeIfNeeded()
        let ancho = ceil(pila.fittingSize.width)
        var marco = panel.frame
        marco.origin.y += marco.height - Self.alto
        marco.size = NSSize(width: ancho, height: Self.alto)
        panel.setFrame(marco, display: true)
        panel.invalidateShadow()
    }

    /// Abajo a la izquierda de la pantalla principal.
    private func colocarPorDefecto() {
        guard let pantalla = NSScreen.main ?? NSScreen.screens.first else { return }
        let area = pantalla.visibleFrame
        panel.setFrameOrigin(NSPoint(x: area.minX + Self.margen, y: area.minY + Self.margen))
    }

    /// La posición guardada puede quedar fuera si se desconectó un monitor.
    private func visibleEnAlgunaPantalla() -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(panel.frame) }
    }

    private static func reloj(_ segundos: Int) -> String {
        String(format: "%d:%02d", segundos / 60, segundos % 60)
    }

    private static func simbolo(_ nombre: String, _ color: NSColor) -> NSImage? {
        NSImage(systemSymbolName: nombre, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold).applying(.init(paletteColors: [color])))
    }
}

// MARK: - Vistas

/// Fondo de la píldora: arrastrar desde él mueve el panel.
private final class Fondo: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Etiqueta que también deja arrastrar el panel.
private final class Etiqueta: NSTextField {
    override var mouseDownCanMoveWindow: Bool { true }
}

/// Botón circular con un símbolo; responde al primer clic aunque la app no esté activa.
private final class BotonRedondo: NSButton {
    private static let lado: CGFloat = 32
    private static let fondoNormal = NSColor(white: 1, alpha: 0.1)
    private let color: NSColor
    private var fondo = BotonRedondo.fondoNormal
    private var simbolo = ""
    private var descripcion = ""

    init(simbolo: String, descripcion: String, color: NSColor = NSColor(white: 0.93, alpha: 1)) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: Self.lado, height: Self.lado))
        isBordered = false
        title = ""
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = Self.lado / 2
        layer?.backgroundColor = fondo.cgColor
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.lado).isActive = true
        heightAnchor.constraint(equalToConstant: Self.lado).isActive = true
        cambiar(simbolo: simbolo, descripcion: descripcion)
    }

    required init?(coder: NSCoder) { fatalError() }

    func cambiar(simbolo: String, descripcion: String) {
        self.simbolo = simbolo
        self.descripcion = descripcion
        pintarSimbolo(color)
        toolTip = descripcion
    }

    /// Fondo rojo y símbolo blanco (p. ej. la papelera mientras pide confirmación).
    func resaltar(_ activo: Bool) {
        fondo = activo ? .systemRed : Self.fondoNormal
        layer?.backgroundColor = fondo.cgColor
        pintarSimbolo(activo ? .white : color)
    }

    private func pintarSimbolo(_ tinte: NSColor) {
        image = NSImage(systemSymbolName: simbolo, accessibilityDescription: descripcion)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .bold).applying(.init(paletteColors: [tinte])))
    }

    override func acceptsFirstMouse(for evento: NSEvent?) -> Bool { true }

    override func mouseDown(with evento: NSEvent) {
        let normal = fondo
        layer?.backgroundColor = normal.blended(withFraction: 0.15, of: .white)?.cgColor
        super.mouseDown(with: evento)  // bucle de seguimiento hasta soltar
        if fondo == normal { layer?.backgroundColor = fondo.cgColor }  // la acción pudo cambiarlo
    }
}

/// Botón en píldora con un punto de color y texto («● Grabar»).
private final class BotonPildora: NSButton {
    private static let alto: CGFloat = 32
    private static let relleno = NSColor(srgbRed: 0xd6 / 255, green: 0x7f / 255, blue: 0x48 / 255, alpha: 1)

    init(titulo: String) {
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = Self.alto / 2
        layer?.backgroundColor = Self.relleno.cgColor
        focusRingType = .none
        // El punto va dentro del texto para que quede pegado a él y todo centrado.
        let punto = NSTextAttachment()
        punto.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold).applying(.init(paletteColors: [.white])))
        if let tamano = punto.image?.size {
            punto.bounds = NSRect(x: 0, y: 1, width: tamano.width, height: tamano.height)
        }
        let texto = NSMutableAttributedString(attachment: punto)
        texto.append(NSAttributedString(string: "  \(titulo)"))
        let parrafo = NSMutableParagraphStyle()
        parrafo.alignment = .center
        texto.addAttributes([
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: parrafo,
        ], range: NSRange(location: 0, length: texto.length))
        imagePosition = .noImage
        attributedTitle = texto
        toolTip = "Iniciar grabación (⌥⇧L)"
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: Self.alto).isActive = true
        widthAnchor.constraint(equalToConstant: ceil(attributedTitle.size().width) + 36).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for evento: NSEvent?) -> Bool { true }

    override func mouseDown(with evento: NSEvent) {
        layer?.backgroundColor = Self.relleno.blended(withFraction: 0.2, of: .black)?.cgColor
        super.mouseDown(with: evento)
        layer?.backgroundColor = Self.relleno.cgColor
    }
}
