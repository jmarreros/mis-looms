import Foundation
import Security

/// URL del servidor (UserDefaults) y token de la API (Llavero de macOS).
/// Para pruebas y scripts, las variables MISLOOMS_URL y MISLOOMS_TOKEN tienen prioridad
/// y no se toca el Llavero.
enum Configuracion {
    private static let claveURL = "urlServidor"
    private static let servicio = "org.mislooms.Recorder"
    private static let cuenta = "token-api"

    struct ErrorLlavero: LocalizedError {
        let estado: OSStatus
        var errorDescription: String? {
            "No se pudo guardar el token en el Llavero (\(SecCopyErrorMessageString(estado, nil) as String? ?? "error \(estado)"))."
        }
    }

    /// Acepta "midominio.com", "https://midominio.com/" o "…/api" y devuelve la base sin barra final.
    static func normalizar(_ texto: String) -> String? {
        var t = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "https://" + t }
        while t.hasSuffix("/") { t.removeLast() }
        if t.hasSuffix("/api") { t.removeLast(4) }
        guard let url = URL(string: t), url.host != nil, ["http", "https"].contains(url.scheme) else { return nil }
        return t
    }

    static var urlServidor: String? {
        if let v = ProcessInfo.processInfo.environment["MISLOOMS_URL"] { return normalizar(v) }
        return UserDefaults.standard.string(forKey: claveURL)
    }

    static var token: String? {
        if let v = ProcessInfo.processInfo.environment["MISLOOMS_TOKEN"], !v.isEmpty { return v }
        var resultado: AnyObject?
        let consulta: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: cuenta,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess,
              let datos = resultado as? Data else { return nil }
        return String(data: datos, encoding: .utf8)
    }

    static var completa: Bool { urlServidor != nil && !(token ?? "").isEmpty }

    static func guardar(url: String, token: String) throws {
        UserDefaults.standard.set(url, forKey: claveURL)

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: cuenta,
        ]
        let datos = Data(token.utf8)
        var estado = SecItemUpdate(base as CFDictionary, [kSecValueData as String: datos] as CFDictionary)
        if estado == errSecItemNotFound {
            estado = SecItemAdd(base.merging([kSecValueData as String: datos]) { $1 } as CFDictionary, nil)
        }
        guard estado == errSecSuccess else { throw ErrorLlavero(estado: estado) }
    }
}
