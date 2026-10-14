import AppKit

/// Número grande (3, 2, 1) en el centro de la pantalla que se graba, antes de empezar. No recibe
/// clics (no estorba lo que hay debajo) y se cierra antes de iniciar la captura; además, la
/// captura excluye las ventanas de la propia app.
@MainActor
final class CuentaRegresiva {
    private static let lado: CGFloat = 200
    private static let fondo = NSColor(srgbRed: 0x1c / 255, green: 0x1a / 255, blue: 0x17 / 255, alpha: 0.9)
    private static let acento = NSColor(srgbRed: 0xd6 / 255, green: 0x7f / 255, blue: 0x48 / 255, alpha: 1)

    private let ventana: NSPanel
    private let numero = NSTextField(labelWithString: "")
    private let anillo = CAShapeLayer()

    init() {
        ventana = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.lado, height: Self.lado),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        ventana.level = .screenSaver
        ventana.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ventana.ignoresMouseEvents = true
        ventana.isOpaque = false
        ventana.backgroundColor = .clear
        ventana.hasShadow = true
        ventana.isReleasedWhenClosed = false
        ventana.hidesOnDeactivate = false

        let contenido = NSView(frame: NSRect(x: 0, y: 0, width: Self.lado, height: Self.lado))
        contenido.wantsLayer = true
        contenido.layer?.backgroundColor = Self.fondo.cgColor
        contenido.layer?.cornerRadius = Self.lado / 2

        // Anillo terracota que se vacía en cada segundo.
        let margen: CGFloat = 10
        let camino = CGMutablePath()  // desde arriba, en el sentido de las agujas del reloj
        camino.addArc(center: CGPoint(x: Self.lado / 2, y: Self.lado / 2), radius: Self.lado / 2 - margen,
                      startAngle: .pi / 2, endAngle: .pi / 2 - 2 * .pi, clockwise: true)
        anillo.path = camino
        anillo.fillColor = nil
        anillo.strokeColor = Self.acento.cgColor
        anillo.lineWidth = 6
        anillo.lineCap = .round
        contenido.layer?.addSublayer(anillo)

        numero.font = Self.fuenteNumero()
        numero.textColor = .white
        numero.alignment = .center
        numero.translatesAutoresizingMaskIntoConstraints = false
        contenido.addSubview(numero)
        NSLayoutConstraint.activate([
            numero.centerXAnchor.constraint(equalTo: contenido.centerXAnchor),
            numero.centerYAnchor.constraint(equalTo: contenido.centerYAnchor, constant: 4),
        ])
        ventana.contentView = contenido
    }

    /// Muestra (o actualiza) el número en el centro de la pantalla principal.
    func mostrar(_ valor: Int) {
        numero.stringValue = "\(valor)"
        if !ventana.isVisible {
            let pantalla = NSScreen.screens.first ?? NSScreen.main  // la que tiene la barra de menús, la que se graba
            if let marco = pantalla?.frame {
                ventana.setFrameOrigin(NSPoint(x: marco.midX - Self.lado / 2, y: marco.midY - Self.lado / 2))
            }
            ventana.alphaValue = 1
            ventana.orderFrontRegardless()
        }
        animarAnillo()
    }

    func ocultar() {
        anillo.removeAllAnimations()
        ventana.orderOut(nil)
    }

    private func animarAnillo() {
        let animacion = CABasicAnimation(keyPath: "strokeEnd")
        animacion.fromValue = 1
        animacion.toValue = 0
        animacion.duration = 1
        animacion.fillMode = .forwards
        animacion.isRemovedOnCompletion = false
        anillo.removeAllAnimations()
        anillo.add(animacion, forKey: "cuenta")
    }

    /// Redondeada y gruesa, con cifras de ancho fijo.
    private static func fuenteNumero() -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(ofSize: 96, weight: .bold)
        guard let redondeada = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: redondeada, size: 96) ?? base
    }
}
