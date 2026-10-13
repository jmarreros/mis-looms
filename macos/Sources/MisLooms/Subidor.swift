import Foundation

enum ErrorSubida: LocalizedError {
    case archivoNoExiste(String)
    case s3(Int, parte: Int)

    var errorDescription: String? {
        switch self {
        case .archivoNoExiste(let ruta): "Ya no existe el archivo \((ruta as NSString).lastPathComponent)."
        case .s3(let codigo, let parte): "S3 rechazó la parte \(parte) (HTTP \(codigo))."
        }
    }
}

/// Subida pendiente, guardada en disco para poder reanudarla si la app se cierra o falla.
/// `slug == nil` significa que el servidor todavía no ha creado el video.
struct EstadoSubida: Codable {
    var id = UUID().uuidString
    var archivo: String
    var slug: String?
    var tamano: Int
    var tamanoParte = 0
    var totalPartes = 0
    var meta = Metadatos()
    var partes: [ParteSubida] = []  // las que ya están en S3, con su ETag

    var url: URL { URL(fileURLWithPath: archivo) }

    // MARK: Persistencia

    static var carpeta: URL {
        if let ruta = ProcessInfo.processInfo.environment["MISLOOMS_ESTADO"] { return URL(fileURLWithPath: ruta) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mis Looms/subidas", isDirectory: true)
    }

    static func nueva(archivo: URL) throws -> EstadoSubida {
        let tamano = (try FileManager.default.attributesOfItem(atPath: archivo.path)[.size] as? Int) ?? 0
        let estado = EstadoSubida(archivo: archivo.path, tamano: tamano)
        estado.guardar()
        return estado
    }

    static var hayPendientes: Bool {
        ((try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []).contains { $0.hasSuffix(".json") }
    }

    static func pendientes() -> [EstadoSubida] {
        let archivos = (try? FileManager.default.contentsOfDirectory(at: carpeta, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return archivos.filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? JSONDecoder().decode(EstadoSubida.self, from: Data(contentsOf: $0)) }
    }

    private var archivoDeEstado: URL { Self.carpeta.appendingPathComponent("\(id).json") }

    func guardar() {
        try? FileManager.default.createDirectory(at: Self.carpeta, withIntermediateDirectories: true)
        try? JSONEncoder().encode(self).write(to: archivoDeEstado, options: .atomic)
    }

    func borrar() { try? FileManager.default.removeItem(at: archivoDeEstado) }
}

/// Suma los bytes ya subidos y los que van en vuelo para dar un progreso global.
private final class Medidor: @unchecked Sendable {
    private let cerrojo = NSLock()
    private var subidos: Int64
    private var enVuelo: [Int: Int64] = [:]
    private let total: Int64
    private let alCambiar: @Sendable (Double) -> Void

    init(total: Int, yaSubidos: Int64, alCambiar: @escaping @Sendable (Double) -> Void) {
        self.total = Int64(max(total, 1))
        self.subidos = yaSubidos
        self.alCambiar = alCambiar
    }

    func avance(parte: Int, enviados: Int64) { actualizar { self.enVuelo[parte] = enviados } }
    func reiniciar(parte: Int) { actualizar { self.enVuelo[parte] = nil } }
    func completar(parte: Int, bytes: Int64) { actualizar { self.enVuelo[parte] = nil; self.subidos += bytes } }

    private func actualizar(_ cambio: () -> Void) {
        cerrojo.lock()
        cambio()
        let fraccion = min(1, Double(subidos + enVuelo.values.reduce(0, +)) / Double(total))
        cerrojo.unlock()
        alCambiar(fraccion)
    }
}

/// Informa de los bytes enviados de una petición concreta.
private final class ObservadorEnvio: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let alEnviar: @Sendable (Int64) -> Void
    init(_ alEnviar: @escaping @Sendable (Int64) -> Void) { self.alEnviar = alEnviar }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        alEnviar(totalBytesSent)
    }
}

/// Sube un MP4 a S3 con multipart prefirmado por Laravel: partes en paralelo, reintentos por
/// parte, miniatura y cierre. El estado se guarda tras cada parte para poder reanudar.
struct Subidor {
    static let partesEnParalelo = 3
    static let intentosPorParte = 4

    let api: ClienteAPI
    private let sesion: URLSession

    init(api: ClienteAPI) {
        self.api = api
        let configuracion = URLSessionConfiguration.ephemeral
        configuracion.waitsForConnectivity = true  // si se corta la red, espera en vez de fallar
        configuracion.timeoutIntervalForResource = 600
        sesion = URLSession(configuration: configuracion)
    }

    /// Ejecuta (o reanuda) una subida y devuelve el enlace para compartir.
    /// Si se cancela la tarea, aborta la subida en el servidor y olvida el estado.
    func procesar(_ inicial: EstadoSubida, progreso: @escaping @Sendable (Double) -> Void) async throws -> String {
        var estado = inicial
        do {
            return try await ejecutar(&estado, progreso: progreso)
        } catch {
            let cancelado = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
            if cancelado {
                let slug = estado.slug, api = api
                estado.borrar()
                // En una tarea aparte: la actual está cancelada y su URLSession fallaría al instante.
                if let slug { await Task.detached { try? await api.abortar(slug: slug) }.value }
                throw CancellationError()
            }
            throw error
        }
    }

    // MARK: - Flujo

    private func ejecutar(_ estado: inout EstadoSubida, progreso: @escaping @Sendable (Double) -> Void) async throws -> String {
        guard FileManager.default.fileExists(atPath: estado.archivo) else {
            estado.borrar()
            throw ErrorSubida.archivoNoExiste(estado.archivo)
        }

        // 1. Crear el video en el servidor, o recuperar las URLs de las partes que faltan.
        var firmadas: [Int: URL] = [:]
        if let slug = estado.slug {
            let faltantes = partesFaltantes(estado)
            do {
                if !faltantes.isEmpty {
                    firmadas = Dictionary(uniqueKeysWithValues: try await api.firmar(slug: slug, partes: faltantes).map { ($0.partNumber, $0.url) })
                }
            } catch ErrorAPI.subidaCerrada {
                // Caducó o se canceló en el servidor: empezar de cero con el mismo archivo.
                estado.slug = nil
                estado.partes = []
            }
        }
        if estado.slug == nil {
            estado.meta = await Medios.metadatos(de: estado.url)
            let inicio = try await api.crear(size: estado.tamano, meta: estado.meta)
            estado.slug = inicio.video.slug
            estado.tamanoParte = inicio.partSize
            estado.totalPartes = inicio.parts.count
            firmadas = Dictionary(uniqueKeysWithValues: inicio.parts.map { ($0.partNumber, $0.url) })
        }
        estado.guardar()
        guard let slug = estado.slug else { throw ErrorAPI.respuestaInvalida }

        // 2. Subir las partes que faltan, de 3 en 3.
        let yaSubidos = estado.partes.reduce(Int64(0)) { $0 + Int64(longitudParte($1.partNumber, estado)) }
        let medidor = Medidor(total: estado.tamano, yaSubidos: yaSubidos, alCambiar: progreso)
        medidor.completar(parte: 0, bytes: 0)  // publica el progreso inicial (0 % o lo ya subido)
        var pendientes = partesFaltantes(estado)[...]
        let urls = firmadas
        try await withThrowingTaskGroup(of: ParteSubida.self) { grupo in
            func lanzar(_ parte: Int, _ copia: EstadoSubida) {
                grupo.addTask { try await subirParte(parte, estado: copia, urlInicial: urls[parte], medidor: medidor) }
            }
            for _ in 0..<Self.partesEnParalelo {
                guard let n = pendientes.popFirst() else { break }
                lanzar(n, estado)
            }
            while let parte = try await grupo.next() {
                estado.partes.append(parte)
                estado.guardar()
                if let n = pendientes.popFirst() { lanzar(n, estado) }
            }
        }

        // 3. Miniatura (si falla, el video se publica igualmente sin ella).
        let conMiniatura = try await subirMiniatura(estado, slug: slug)

        // 4. Cerrar la subida.
        do {
            let video = try await api.completar(slug: slug, partes: estado.partes, meta: estado.meta, conMiniatura: conMiniatura)
            estado.borrar()
            return video.shareUrl
        } catch ErrorAPI.subidaCerrada {
            estado.borrar()  // ya no se puede continuar; reintentar solo duplicaría el video
            throw ErrorAPI.subidaCerrada
        }
    }

    private func partesFaltantes(_ estado: EstadoSubida) -> [Int] {
        guard estado.totalPartes > 0 else { return [] }
        let hechas = Set(estado.partes.map(\.partNumber))
        return (1...estado.totalPartes).filter { !hechas.contains($0) }
    }

    /// Todas las partes miden `tamanoParte`, salvo la última, que lleva el resto.
    private func longitudParte(_ numero: Int, _ estado: EstadoSubida) -> Int {
        min(estado.tamanoParte, estado.tamano - (numero - 1) * estado.tamanoParte)
    }

    // MARK: - Partes

    private func subirParte(_ numero: Int, estado: EstadoSubida, urlInicial: URL?, medidor: Medidor) async throws -> ParteSubida {
        let longitud = longitudParte(numero, estado)
        let datos = try leer(estado.url, desde: (numero - 1) * estado.tamanoParte, longitud: longitud)
        var url = urlInicial
        var intento = 0
        while true {
            try Task.checkCancellation()
            do {
                if url == nil, let slug = estado.slug {
                    url = try await api.firmar(slug: slug, partes: [numero]).first?.url
                }
                guard let destino = url else { throw ErrorAPI.respuestaInvalida }
                let etag = try await put(datos, a: destino, parte: numero, medidor: medidor)
                medidor.completar(parte: numero, bytes: Int64(longitud))
                return ParteSubida(partNumber: numero, etag: etag)
            } catch {
                medidor.reiniciar(parte: numero)
                let cancelado = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                intento += 1
                if cancelado || error is ErrorAPI || intento >= Self.intentosPorParte { throw error }
                // 403: la URL prefirmada caducó. Cualquier otro fallo: reintento con espera creciente.
                if case ErrorSubida.s3(403, _) = error { url = nil }
                try await Task.sleep(for: .seconds(1 << (intento - 1)))
            }
        }
    }

    private func put(_ datos: Data, a url: URL, parte: Int, medidor: Medidor,
                     cabeceras: [String: String] = [:]) async throws -> String {
        var peticion = URLRequest(url: url)
        peticion.httpMethod = "PUT"
        for (clave, valor) in cabeceras { peticion.setValue(valor, forHTTPHeaderField: clave) }
        let observador = ObservadorEnvio { medidor.avance(parte: parte, enviados: $0) }
        let (_, respuesta) = try await sesion.upload(for: peticion, from: datos, delegate: observador)
        guard let http = respuesta as? HTTPURLResponse, http.statusCode == 200 else {
            throw ErrorSubida.s3((respuesta as? HTTPURLResponse)?.statusCode ?? 0, parte: parte)
        }
        return http.value(forHTTPHeaderField: "ETag") ?? ""
    }

    private func leer(_ archivo: URL, desde: Int, longitud: Int) throws -> Data {
        let manejador = try FileHandle(forReadingFrom: archivo)
        defer { try? manejador.close() }
        try manejador.seek(toOffset: UInt64(desde))
        return try manejador.read(upToCount: longitud) ?? Data()
    }

    // MARK: - Miniatura

    private func subirMiniatura(_ estado: EstadoSubida, slug: String) async throws -> Bool {
        do {
            let jpg = try await Medios.miniatura(de: estado.url, duracion: estado.meta.duracion)
            let destino = try await api.destinoMiniatura(slug: slug)
            let medidor = Medidor(total: jpg.count, yaSubidos: 0) { _ in }
            _ = try await put(jpg, a: destino.uploadUrl, parte: 0, medidor: medidor, cabeceras: destino.headers)
            return true
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            return false
        }
    }
}
