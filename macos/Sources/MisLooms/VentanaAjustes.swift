import AppKit

/// Ventana para pegar la URL del servidor y el token de la app (se guardan en el Llavero).
@MainActor
final class VentanaAjustes: NSObject, NSWindowDelegate {
    var alGuardar: (() -> Void)?

    private var ventana: NSWindow?
    private let campoURL = NSTextField()
    private let campoToken = NSSecureTextField()
    private let mensaje = NSTextField(wrappingLabelWithString: "")
    private let botonProbar = NSButton(title: "Probar conexión", target: nil, action: nil)
    private let botonGuardar = NSButton(title: "Guardar", target: nil, action: nil)

    func mostrar() {
        if ventana == nil { construir() }
        campoURL.stringValue = Configuracion.urlServidor ?? ""
        campoToken.stringValue = Configuracion.token ?? ""
        decir("")
        NSApp.activate(ignoringOtherApps: true)
        ventana?.makeKeyAndOrderFront(nil)
        ventana?.makeFirstResponder(campoURL.stringValue.isEmpty ? campoURL : campoToken)
    }

    private func construir() {
        campoURL.placeholderString = "https://mis-looms.midominio.com"
        campoToken.placeholderString = "1|abcdef…"

        let titulo = NSTextField(labelWithString: "Conexión con tu servidor")
        titulo.font = .boldSystemFont(ofSize: 15)
        let ayuda = NSTextField(wrappingLabelWithString: "Genera el token en el panel web › Token de la app y pégalo aquí. Se guarda en el Llavero de macOS.")
        ayuda.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        ayuda.textColor = .secondaryLabelColor

        let rejilla = NSGridView(views: [
            [NSTextField(labelWithString: "URL del servidor"), campoURL],
            [NSTextField(labelWithString: "Token de la app"), campoToken],
        ])
        rejilla.columnSpacing = 10
        rejilla.rowSpacing = 10
        rejilla.column(at: 0).xPlacement = .trailing
        rejilla.column(at: 1).width = 300

        botonProbar.target = self
        botonProbar.action = #selector(probar)
        botonGuardar.target = self
        botonGuardar.action = #selector(guardar)
        botonGuardar.keyEquivalent = "\r"
        let botones = NSStackView(views: [botonProbar, botonGuardar])
        botones.spacing = 10

        mensaje.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        mensaje.preferredMaxLayoutWidth = 400

        let pila = NSStackView(views: [titulo, ayuda, rejilla, mensaje, botones])
        pila.orientation = .vertical
        pila.alignment = .leading
        pila.spacing = 14
        pila.setCustomSpacing(18, after: ayuda)
        pila.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        botones.setContentHuggingPriority(.required, for: .horizontal)

        let nueva = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        nueva.title = "Ajustes de Mis Looms"
        nueva.contentView = pila
        nueva.isReleasedWhenClosed = false
        nueva.delegate = self
        nueva.center()
        ventana = nueva
    }

    private func datos() -> (url: String, token: String)? {
        guard let url = Configuracion.normalizar(campoURL.stringValue) else {
            decir("La URL del servidor no es válida.", error: true)
            return nil
        }
        let token = campoToken.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            decir("Falta el token.", error: true)
            return nil
        }
        return (url, token)
    }

    @objc private func probar() {
        guard let (url, token) = datos() else { return }
        botonProbar.isEnabled = false
        decir("Probando…")
        Task {
            defer { botonProbar.isEnabled = true }
            do {
                try await ClienteAPI(url: url, token: token).probar()
                decir("✓ Conexión correcta.")
            } catch let error as URLError {
                decir("No se pudo conectar con \(url): \(error.localizedDescription)", error: true)
            } catch {
                decir(error.localizedDescription, error: true)
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
            decir(error.localizedDescription, error: true)
        }
    }

    private func decir(_ texto: String, error: Bool = false) {
        mensaje.stringValue = texto
        mensaje.textColor = error ? .systemRed : .secondaryLabelColor
        mensaje.isHidden = texto.isEmpty
    }
}
