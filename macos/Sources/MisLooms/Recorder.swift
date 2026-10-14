import AVFoundation
import ScreenCaptureKit

enum RecorderError: LocalizedError {
    case sinPantalla
    case escritor(String)

    var errorDescription: String? {
        switch self {
        case .sinPantalla: return "No se encontró ninguna pantalla para grabar."
        case .escritor(let detalle): return "Error al escribir el video: \(detalle)"
        }
    }
}

/// Graba la pantalla principal completa + micrófono (+ audio del sistema opcional)
/// a un MP4 H.264 + AAC con ScreenCaptureKit y AVAssetWriter.
final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate {
    static let anchoMaximo = 1920
    static let altoMaximo = 1080
    static let bitrate = 8_000_000
    static let fps = 30

    /// Se invoca (en un hilo cualquiera) si la captura se detiene sola por un error.
    var alDetenerseConError: ((Error) -> Void)?

    private let cola = DispatchQueue(label: "org.mislooms.captura")
    private var stream: SCStream?
    private var escritor: AVAssetWriter?
    private var entradaVideo: AVAssetWriterInput?
    private var entradaMicrofono: AVAssetWriterInput?
    private var entradaSistema: AVAssetWriterInput?
    private var sesionIniciada = false
    private var finalizando = false

    // Pausa (solo se tocan en `cola`). Las muestras llegan con la hora del reloj del sistema:
    // durante la pausa se descartan y, al reanudar, a todas se les resta el tiempo pausado
    // acumulado para que el MP4 continúe sin huecos.
    private var enPausa = false
    private var inicioPausa = CMTime.invalid
    private var reanudadoEn = CMTime.invalid
    private var desfase = CMTime.zero

    private(set) var archivo: URL?
    private(set) var pausado = false  // copia para el hilo principal

    var grabando: Bool { stream != nil }

    // MARK: - Inicio

    func iniciar(destino: URL, audioDelSistema: Bool) async throws {
        // Lanza el diálogo de permiso de Grabación de pantalla la primera vez.
        let contenido = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let principal = CGMainDisplayID()
        guard let pantalla = contenido.displays.first(where: { $0.displayID == principal })
                ?? contenido.displays.first else { throw RecorderError.sinPantalla }

        // Las ventanas de la propia app (controles flotantes, Ajustes) no salen en el video.
        let propia = contenido.applications.filter { $0.processID == getpid() }
        let filtro = SCContentFilter(display: pantalla, excludingApplications: propia, exceptingWindows: [])
        let (ancho, alto) = Self.dimensiones(pantalla: pantalla, filtro: filtro)

        let config = SCStreamConfiguration()
        config.width = ancho
        config.height = alto
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Self.fps))
        config.showsCursor = true
        config.queueDepth = 6
        config.capturesAudio = audioDelSistema
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = true
        config.sampleRate = 48_000
        config.channelCount = 2

        try prepararEscritor(destino: destino, ancho: ancho, alto: alto, audioDelSistema: audioDelSistema)

        let nuevo = SCStream(filter: filtro, configuration: config, delegate: self)
        try nuevo.addStreamOutput(self, type: .screen, sampleHandlerQueue: cola)
        try nuevo.addStreamOutput(self, type: .microphone, sampleHandlerQueue: cola)
        if audioDelSistema {
            try nuevo.addStreamOutput(self, type: .audio, sampleHandlerQueue: cola)
        }
        try await nuevo.startCapture()
        stream = nuevo
        archivo = destino
    }

    /// Resolución de salida: píxeles reales de la pantalla reducidos a 1080p máx., en pares.
    private static func dimensiones(pantalla: SCDisplay, filtro: SCContentFilter) -> (Int, Int) {
        let escala = Double(filtro.pointPixelScale)
        let nativoAncho = Double(pantalla.width) * escala
        let nativoAlto = Double(pantalla.height) * escala
        let factor = min(1, Double(anchoMaximo) / nativoAncho, Double(altoMaximo) / nativoAlto)
        let par = { (v: Double) in max(2, Int((v * factor).rounded()) & ~1) }
        return (par(nativoAncho), par(nativoAlto))
    }

    private func prepararEscritor(destino: URL, ancho: Int, alto: Int, audioDelSistema: Bool) throws {
        try? FileManager.default.removeItem(at: destino)
        let w = try AVAssetWriter(outputURL: destino, fileType: .mp4)
        // moov al inicio (faststart): el video se reproduce sin descargarlo entero.
        w.shouldOptimizeForNetworkUse = true

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: ancho,
            AVVideoHeightKey: alto,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalDurationKey: 2,
                AVVideoExpectedSourceFrameRateKey: Self.fps,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        w.add(video)

        let ajustesAudio: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000,
        ]
        let micro = AVAssetWriterInput(mediaType: .audio, outputSettings: ajustesAudio)
        micro.expectsMediaDataInRealTime = true
        w.add(micro)

        // TODO(mezcla): con audio del sistema se escribe como segunda pista. El <video> web
        // solo reproduce la primera; para el enlace público habrá que mezclarlas en una.
        var sistema: AVAssetWriterInput?
        if audioDelSistema {
            let e = AVAssetWriterInput(mediaType: .audio, outputSettings: ajustesAudio)
            e.expectsMediaDataInRealTime = true
            w.add(e)
            sistema = e
        }

        guard w.startWriting() else {
            throw RecorderError.escritor(w.error?.localizedDescription ?? "no se pudo iniciar")
        }
        escritor = w
        entradaVideo = video
        entradaMicrofono = micro
        entradaSistema = sistema
        sesionIniciada = false
        finalizando = false
        enPausa = false
        inicioPausa = .invalid
        reanudadoEn = .invalid
        desfase = .zero
        pausado = false
    }

    // MARK: - Pausa

    func pausar() {
        guard grabando, !pausado else { return }
        pausado = true
        let ahora = CMClockGetTime(CMClockGetHostTimeClock())
        cola.async {
            self.enPausa = true
            self.inicioPausa = ahora
        }
    }

    func reanudar() {
        guard grabando, pausado else { return }
        pausado = false
        let ahora = CMClockGetTime(CMClockGetHostTimeClock())
        cola.async {
            guard self.enPausa else { return }
            self.enPausa = false
            self.desfase = CMTimeAdd(self.desfase, CMTimeSubtract(ahora, self.inicioPausa))
            self.reanudadoEn = ahora
        }
    }

    // MARK: - Fin

    /// Detiene la captura, cierra el MP4 y devuelve su ruta.
    func detener() async throws -> URL {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        return try await finalizar()
    }

    /// Detiene la captura sin guardar nada y borra el archivo a medias.
    func descartar() async {
        if let stream {
            try? await stream.stopCapture()
            self.stream = nil
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            cola.async {
                self.finalizando = true
                if self.escritor?.status == .writing { self.escritor?.cancelWriting() }
                cont.resume()
            }
        }
        escritor = nil; entradaVideo = nil; entradaMicrofono = nil; entradaSistema = nil
        if let archivo { try? FileManager.default.removeItem(at: archivo) }
        archivo = nil
        pausado = false
    }

    private func finalizar() async throws -> URL {
        let url = archivo
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            cola.async {
                guard let w = self.escritor, !self.finalizando else { cont.resume(); return }
                self.finalizando = true
                guard self.sesionIniciada else {
                    w.cancelWriting()
                    cont.resume()
                    return
                }
                self.entradaVideo?.markAsFinished()
                self.entradaMicrofono?.markAsFinished()
                self.entradaSistema?.markAsFinished()
                w.finishWriting { cont.resume() }
            }
        }
        defer {
            escritor = nil; entradaVideo = nil; entradaMicrofono = nil; entradaSistema = nil
        }
        if let w = escritor, w.status == .failed {
            throw RecorderError.escritor(w.error?.localizedDescription ?? "desconocido")
        }
        guard let url, sesionIniciada else {
            throw RecorderError.escritor("no se capturó ningún fotograma")
        }
        return url
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of tipo: SCStreamOutputType) {
        guard buffer.isValid, !finalizando, !enPausa, let w = escritor, w.status == .writing else { return }
        // Muestras de antes de reanudar que llegan tarde: se descartan para no retroceder en el tiempo.
        if reanudadoEn.isValid, CMTimeCompare(buffer.presentationTimeStamp, reanudadoEn) < 0 { return }
        guard let buffer = desplazado(buffer) else { return }

        switch tipo {
        case .screen:
            guard Self.fotogramaCompleto(buffer), let entrada = entradaVideo else { return }
            if !sesionIniciada {
                w.startSession(atSourceTime: buffer.presentationTimeStamp)
                sesionIniciada = true
            }
            if entrada.isReadyForMoreMediaData { entrada.append(buffer) }
        case .microphone:
            guard sesionIniciada, let entrada = entradaMicrofono, entrada.isReadyForMoreMediaData else { return }
            entrada.append(buffer)
        case .audio:
            guard sesionIniciada, let entrada = entradaSistema, entrada.isReadyForMoreMediaData else { return }
            entrada.append(buffer)
        @unknown default:
            break
        }
    }

    /// Copia de la muestra con los tiempos adelantados en el tiempo pausado acumulado.
    private func desplazado(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard desfase != .zero else { return buffer }
        guard var tiempos = try? buffer.sampleTimingInfos() else { return nil }
        for i in tiempos.indices {
            tiempos[i].presentationTimeStamp = CMTimeSubtract(tiempos[i].presentationTimeStamp, desfase)
            if tiempos[i].decodeTimeStamp.isValid {
                tiempos[i].decodeTimeStamp = CMTimeSubtract(tiempos[i].decodeTimeStamp, desfase)
            }
        }
        return try? CMSampleBuffer(copying: buffer, withNewTiming: tiempos)
    }

    /// ScreenCaptureKit también entrega buffers "idle"/"blank" sin imagen: se descartan.
    private static func fotogramaCompleto(_ buffer: CMSampleBuffer) -> Bool {
        guard let adjuntos = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let estado = adjuntos.first?[.status] as? Int else { return false }
        return estado == SCFrameStatus.complete.rawValue
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
        alDetenerseConError?(error)
    }
}
