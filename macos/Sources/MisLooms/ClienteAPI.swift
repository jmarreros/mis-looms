import Foundation

/// Errores de la API de Mis Looms, con mensajes listos para mostrar.
enum ErrorAPI: LocalizedError {
    case sinConfigurar
    case tokenInvalido
    case subidaCerrada  // 409: la subida ya no está en curso (completada, abortada o caducada)
    case servidor(Int, String)
    case respuestaInvalida

    var errorDescription: String? {
        switch self {
        case .sinConfigurar: "Falta configurar la URL del servidor y el token (menú › Ajustes)."
        case .tokenInvalido: "El servidor rechazó el token. Genera uno nuevo en el panel › Token de la app."
        case .subidaCerrada: "El servidor ya no tiene abierta esta subida."
        case .servidor(let codigo, let mensaje): "El servidor respondió \(codigo): \(mensaje)"
        case .respuestaInvalida: "El servidor devolvió una respuesta inesperada."
        }
    }
}

struct VideoRemoto: Decodable {
    let slug: String
    let shareUrl: String
}

struct ParteFirmada: Decodable {
    let partNumber: Int
    let url: URL
}

struct ParteSubida: Codable, Equatable {
    let partNumber: Int
    let etag: String
}

struct Metadatos: Codable {
    var duracion: Double?
    var ancho: Int?
    var alto: Int?
}

struct SubidaIniciada: Decodable {
    let video: VideoRemoto
    let uploadId: String
    let partSize: Int
    let parts: [ParteFirmada]
}

struct DestinoMiniatura: Decodable {
    let uploadUrl: URL
    let headers: [String: String]
}

/// Cliente de la API de docs/api.md. Solo habla con Laravel; las partes y la miniatura
/// se suben directo a S3 desde `Subidor`.
struct ClienteAPI {
    let base: URL
    let token: String
    var sesion: URLSession = .shared

    init() throws {
        guard let url = Configuracion.urlServidor, let token = Configuracion.token, !token.isEmpty,
              let base = URL(string: url + "/api") else { throw ErrorAPI.sinConfigurar }
        self.base = base
        self.token = token
    }

    init(url: String, token: String) throws {
        guard let normalizada = Configuracion.normalizar(url), let base = URL(string: normalizada + "/api") else {
            throw ErrorAPI.sinConfigurar
        }
        self.base = base
        self.token = token
    }

    func probar() async throws {
        _ = try await enviar("GET", "ping", cuerpo: nil)
    }

    func crear(size: Int, meta: Metadatos) async throws -> SubidaIniciada {
        try await pedir(SubidaIniciada.self, "POST", "videos", cuerpo: ["size": size].merging(campos(meta)) { $1 })
    }

    func firmar(slug: String, partes: [Int]) async throws -> [ParteFirmada] {
        struct Respuesta: Decodable { let parts: [ParteFirmada] }
        return try await pedir(Respuesta.self, "POST", "videos/\(slug)/parts", cuerpo: ["parts": partes]).parts
    }

    func destinoMiniatura(slug: String) async throws -> DestinoMiniatura {
        try await pedir(DestinoMiniatura.self, "POST", "videos/\(slug)/thumbnail", cuerpo: [:])
    }

    func completar(slug: String, partes: [ParteSubida], meta: Metadatos, conMiniatura: Bool) async throws -> VideoRemoto {
        struct Respuesta: Decodable { let video: VideoRemoto }
        var cuerpo = campos(meta)
        cuerpo["parts"] = partes.sorted { $0.partNumber < $1.partNumber }
            .map { ["part_number": $0.partNumber, "etag": $0.etag] as [String: Any] }
        cuerpo["has_thumbnail"] = conMiniatura
        return try await pedir(Respuesta.self, "POST", "videos/\(slug)/complete", cuerpo: cuerpo).video
    }

    func abortar(slug: String) async throws {
        _ = try await enviar("POST", "videos/\(slug)/abort", cuerpo: [:])
    }

    // MARK: - Internos

    private func campos(_ meta: Metadatos) -> [String: Any] {
        var c: [String: Any] = [:]
        if let d = meta.duracion { c["duration"] = d }
        if let a = meta.ancho { c["width"] = a }
        if let a = meta.alto { c["height"] = a }
        return c
    }

    private func pedir<T: Decodable>(_ tipo: T.Type, _ metodo: String, _ ruta: String, cuerpo: [String: Any]?) async throws -> T {
        let datos = try await enviar(metodo, ruta, cuerpo: cuerpo)
        let decodificador = JSONDecoder()
        decodificador.keyDecodingStrategy = .convertFromSnakeCase
        guard let resultado = try? decodificador.decode(T.self, from: datos) else { throw ErrorAPI.respuestaInvalida }
        return resultado
    }

    private func enviar(_ metodo: String, _ ruta: String, cuerpo: [String: Any]?) async throws -> Data {
        var peticion = URLRequest(url: base.appendingPathComponent(ruta))
        peticion.httpMethod = metodo
        peticion.timeoutInterval = 30
        peticion.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        peticion.setValue("application/json", forHTTPHeaderField: "Accept")
        if let cuerpo {
            peticion.setValue("application/json", forHTTPHeaderField: "Content-Type")
            peticion.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)
        }
        let (datos, respuesta) = try await sesion.data(for: peticion)
        guard let http = respuesta as? HTTPURLResponse else { throw ErrorAPI.respuestaInvalida }
        switch http.statusCode {
        case 200..<300: return datos
        case 401: throw ErrorAPI.tokenInvalido
        case 409: throw ErrorAPI.subidaCerrada
        default:
            let mensaje = (try? JSONSerialization.jsonObject(with: datos) as? [String: Any])?["message"] as? String
            throw ErrorAPI.servidor(http.statusCode, mensaje ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
    }
}
