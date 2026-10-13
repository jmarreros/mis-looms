import AppKit

/// Ventana para pegar la URL del servidor y el token de la app (se guardan en el Llavero).
@MainActor
final class VentanaAjustes: NSObject, NSWindowDelegate {
    var alGuardar: (() -> Void)?

    private static let anchoVentana: CGFloat = 480
    private static let margen: CGFloat = 28

    private var ventana: NSWindow?
    private let campoURL = NSTextField()
    private let campoToken = NSSecureTextField()
    private let aviso = AvisoColor(ancho: anchoVentana - 2 * margen)
    private let botonProbar = BotonPildora(titulo: "Probar conexión", primario: false)
    private let botonGuardar = BotonPildora(titulo: "Guardar", primario: true)

    func mostrar() {
        if ventana == nil { construir() }
        campoURL.stringValue = Configuracion.urlServidor ?? ""
        campoToken.stringValue = Configuracion.token ?? ""
        decir("")
        NSApp.activate(ignoringOtherApps: true)
        ventana?.makeKeyAndOrderFront(nil)
        ventana?.makeFirstResponder(campoURL.stringValue.isEmpty ? campoURL : campoToken)
    }

    // MARK: - Construcción

    private func construir() {
        let ancho = Self.anchoVentana - 2 * Self.margen

        configurar(campoURL, marcador: "https://mis-looms.midominio.com")
        configurar(campoToken, marcador: "1|abcdef…")

        let titulo = NSTextField(labelWithString: "Conexión con tu servidor")
        titulo.font = .systemFont(ofSize: 17, weight: .bold)

        let ayuda = NSTextField(wrappingLabelWithString: "Genera el token en el panel web › Token de la app y pégalo aquí. Se guarda en el Llavero de macOS.")
        ayuda.font = .systemFont(ofSize: 13)
        ayuda.textColor = .secondaryLabelColor
        ayuda.preferredMaxLayoutWidth = ancho

        let grupoURL = grupo("URL del servidor", campoURL)
        let grupoToken = grupo("Token de la app", campoToken)

        botonProbar.target = self
        botonProbar.action = #selector(probar)
        botonGuardar.target = self
        botonGuardar.action = #selector(guardar)
        botonGuardar.keyEquivalent = "\r"
        let separador = NSView()
        separador.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let botones = NSStackView(views: [botonProbar, separador, botonGuardar])
        botones.orientation = .horizontal
        botones.spacing = 12

        let pila = NSStackView(views: [titulo, ayuda, grupoURL, grupoToken, aviso, botones])
        pila.orientation = .vertical
        pila.alignment = .leading
        pila.spacing = 18
        pila.setCustomSpacing(8, after: titulo)
        pila.setCustomSpacing(24, after: ayuda)
        pila.setCustomSpacing(22, after: grupoToken)
        pila.setCustomSpacing(24, after: aviso)
        pila.translatesAutoresizingMaskIntoConstraints = false

        // Todo lo que debe ocupar el ancho útil, con restricción explícita: el texto que se
        // parte en varias líneas necesita saber su ancho para calcular bien su alto.
        for vista in [ayuda, grupoURL, grupoToken, aviso, botones] {
            vista.widthAnchor.constraint(equalToConstant: ancho).isActive = true
        }

        let contenedor = NSView()
        contenedor.addSubview(pila)
        NSLayoutConstraint.activate([
            pila.topAnchor.constraint(equalTo: contenedor.topAnchor, constant: Self.margen),
            pila.bottomAnchor.constraint(equalTo: contenedor.bottomAnchor, constant: -Self.margen),
            pila.leadingAnchor.constraint(equalTo: contenedor.leadingAnchor, constant: Self.margen),
            pila.trailingAnchor.constraint(equalTo: contenedor.trailingAnchor, constant: -Self.margen),
        ])

        let nueva = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        nueva.title = "Ajustes de Mis Looms"
        nueva.contentView = contenedor
        nueva.isReleasedWhenClosed = false
        nueva.delegate = self
        ventana = nueva
        ajustarAlto()
        nueva.center()
    }

    /// Campo sin borde (lo enmarca `CampoRedondeado`) y de una sola línea: un token largo
    /// se desplaza en vez de partirse en varias líneas.
    private func configurar(_ campo: NSTextField, marcador: String) {
        campo.placeholderString = marcador
        campo.isBordered = false
        campo.drawsBackground = false
        campo.focusRingType = .none
        campo.font = .systemFont(ofSize: 14)
        campo.usesSingleLineMode = true
        campo.maximumNumberOfLines = 1
        campo.lineBreakMode = .byTruncatingTail
        campo.cell?.wraps = false
        campo.cell?.isScrollable = true
    }

    /// Etiqueta encima de un campo que ocupa todo el ancho.
    private func grupo(_ texto: String, _ campo: NSTextField) -> NSStackView {
        let etiqueta = NSTextField(labelWithString: texto)
        etiqueta.font = .systemFont(ofSize: 13, weight: .semibold)
        let marco = CampoRedondeado(campo)
        let pila = NSStackView(views: [etiqueta, marco])
        pila.orientation = .vertical
        pila.alignment = .leading
        pila.spacing = 8
        marco.widthAnchor.constraint(equalTo: pila.widthAnchor).isActive = true
        marco.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return pila
    }

    /// Ajusta el alto de la ventana a su contenido (el aviso aparece y desaparece), manteniendo el borde superior.
    private func ajustarAlto() {
        guard let ventana, let contenedor = ventana.contentView else { return }
        contenedor.layoutSubtreeIfNeeded()
        let nuevo = ventana.frameRect(forContentRect: NSRect(origin: .zero, size: contenedor.fittingSize)).size
        var marco = ventana.frame
        marco.origin.y += marco.height - nuevo.height
        marco.size = nuevo
        ventana.setFrame(marco, display: true, animate: false)
    }

    // MARK: - Acciones

    private func datos() -> (url: String, token: String)? {
        guard let url = Configuracion.normalizar(campoURL.stringValue) else {
            decir("La URL del servidor no es válida.", .error)
            return nil
        }
        let token = campoToken.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            decir("Falta el token.", .error)
            return nil
        }
        return (url, token)
    }

    @objc private func probar() {
        guard let (url, token) = datos() else { return }
        botonProbar.isEnabled = false
        decir("Probando la conexión…", .info)
        Task {
            defer { botonProbar.isEnabled = true }
            do {
                try await ClienteAPI(url: url, token: token).probar()
                decir("Conexión correcta: el servidor aceptó el token.", .ok)
            } catch let error as URLError {
                decir("No se pudo conectar con \(url): \(error.localizedDescription)", .error)
            } catch {
                decir(error.localizedDescription, .error)
            }
        }
    }

    @objc private func guardar() {
        guard let (url, token) = datos() else { return }
        do {
            try Configuracion.guardar(url: url, token: token)
            ventana?.close()
            alGuardar?()
        } catch {
            decir(error.localizedDescription, .error)
        }
    }

    private func decir(_ texto: String, _ tipo: AvisoColor.Tipo = .info) {
        aviso.mostrar(texto, tipo)
        ajustarAlto()
    }
}

// MARK: - Controles propios

/// Marco en píldora para un campo de texto: borde que se vuelve naranja al enfocarlo.
private final class CampoRedondeado: NSView {
    private let campo: NSTextField
    private var observacion: NSKeyValueObservation?

    init(_ campo: NSTextField) {
        self.campo = campo
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.borderWidth = 1.5
        campo.translatesAutoresizingMaskIntoConstraints = false
        addSubview(campo)
        NSLayoutConstraint.activate([
            campo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            campo.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            campo.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Pulsar en cualquier parte de la píldora enfoca el campo.
    override func mouseDown(with evento: NSEvent) { window?.makeFirstResponder(campo) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observacion = window?.observe(\.firstResponder, options: [.initial]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
    }

    /// Mientras se edita, el primer respondedor es el editor de texto del campo, no el campo.
    private var enfocado: Bool { (window?.firstResponder as? NSText)?.delegate === campo }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            layer?.borderColor = (enfocado ? NSColor(srgbRed: 0.84, green: 0.50, blue: 0.28, alpha: 1)  // #d67f48
                                           : NSColor.separatorColor).cgColor
        }
    }
}

/// Botón en píldora con mucho padding. El principal usa el naranja de la marca.
private final class BotonPildora: NSButton {
    private let primario: Bool
    private static let fuente = NSFont.systemFont(ofSize: 14, weight: .semibold)

    init(titulo: String, primario: Bool) {
        self.primario = primario
        super.init(frame: .zero)
        self.title = titulo
        isBordered = false
        setButtonType(.momentaryChange)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let texto = (title as NSString).size(withAttributes: [.font: Self.fuente])
        return NSSize(width: ceil(texto.width) + 56, height: 42)
    }

    override func draw(_ dirtyRect: NSRect) {
        let forma = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        let fondo: NSColor
        let tinta: NSColor
        if primario {
            fondo = isHighlighted ? NSColor(srgbRed: 0.70, green: 0.38, blue: 0.18, alpha: 1)  // #b2622d
                                  : NSColor(srgbRed: 0.84, green: 0.50, blue: 0.28, alpha: 1)  // #d67f48
            tinta = NSColor(srgbRed: 0.11, green: 0.10, blue: 0.09, alpha: 1)  // #1c1a17
        } else {
            fondo = NSColor.labelColor.withAlphaComponent(isHighlighted ? 0.20 : 0.10)
            tinta = .labelColor
        }
        (isEnabled ? fondo : fondo.withAlphaComponent(0.4)).setFill()
        forma.fill()

        let texto = NSAttributedString(string: title, attributes: [
            .font: Self.fuente, .foregroundColor: isEnabled ? tinta : tinta.withAlphaComponent(0.5),
        ])
        let medida = texto.size()
        texto.draw(at: NSPoint(x: (bounds.width - medida.width) / 2, y: (bounds.height - medida.height) / 2))
    }
}

/// Aviso con color e icono: verde si todo fue bien, rojo si falló, gris mientras se trabaja.
private final class AvisoColor: NSView {
    enum Tipo {
        case info, ok, error

        var color: NSColor {
            switch self {
            case .info: .secondaryLabelColor
            case .ok: .systemGreen
            case .error: .systemRed
            }
        }

        var simbolo: String {
            switch self {
            case .info: "arrow.triangle.2.circlepath"
            case .ok: "checkmark.circle.fill"
            case .error: "exclamationmark.triangle.fill"
            }
        }
    }

    private let icono = NSImageView()
    private let texto = NSTextField(wrappingLabelWithString: "")
    private var tipo = Tipo.info

    init(ancho: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        isHidden = true

        icono.symbolConfiguration = .init(pointSize: 17, weight: .semibold)
        icono.setContentHuggingPriority(.required, for: .horizontal)
        icono.widthAnchor.constraint(equalToConstant: 22).isActive = true

        texto.font = .systemFont(ofSize: 13, weight: .medium)
        texto.preferredMaxLayoutWidth = ancho - 2 * 16 - 22 - 12

        let pila = NSStackView(views: [icono, texto])
        pila.orientation = .horizontal
        pila.alignment = .centerY
        pila.spacing = 12
        pila.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        pila.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pila)
        NSLayoutConstraint.activate([
            pila.topAnchor.constraint(equalTo: topAnchor),
            pila.bottomAnchor.constraint(equalTo: bottomAnchor),
            pila.leadingAnchor.constraint(equalTo: leadingAnchor),
            pila.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func mostrar(_ mensaje: String, _ nuevoTipo: Tipo) {
        isHidden = mensaje.isEmpty
        guard !mensaje.isEmpty else { return }
        tipo = nuevoTipo
        texto.stringValue = mensaje
        icono.image = NSImage(systemSymbolName: nuevoTipo.simbolo, accessibilityDescription: nil)
        icono.contentTintColor = nuevoTipo.color
        needsDisplay = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = tipo.color.withAlphaComponent(0.16).cgColor
            layer?.borderColor = tipo.color.withAlphaComponent(0.45).cgColor
        }
    }
}
