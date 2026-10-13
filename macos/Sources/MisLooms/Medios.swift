import AppKit
import AVFoundation

/// Procesamiento en el cliente (el hosting no tiene ffmpeg): metadatos y miniatura del MP4.
enum Medios {
    static func metadatos(de archivo: URL) async -> Metadatos {
        let asset = AVURLAsset(url: archivo)
        var meta = Metadatos()
        if let duracion = try? await asset.load(.duration), duracion.isNumeric {
            meta.duracion = (duracion.seconds * 10).rounded() / 10
        }
        if let pista = try? await asset.loadTracks(withMediaType: .video).first,
           let tamano = try? await pista.load(.naturalSize) {
            meta.ancho = Int(tamano.width)
            meta.alto = Int(tamano.height)
        }
        return meta
    }

    /// JPG del segundo 1 (o de la mitad si el video dura menos), de hasta 1280×720.
    static func miniatura(de archivo: URL, duracion: Double?) async throws -> Data {
        let generador = AVAssetImageGenerator(asset: AVURLAsset(url: archivo))
        generador.appliesPreferredTrackTransform = true
        generador.maximumSize = CGSize(width: 1280, height: 720)
        // Sin tolerancia, AVFoundation salta al fotograma clave más cercano (normalmente el 0, a menudo vacío).
        generador.requestedTimeToleranceBefore = .zero
        generador.requestedTimeToleranceAfter = .zero
        let segundo = min(1, (duracion ?? 2) / 2)
        let (imagen, _) = try await generador.image(at: CMTime(seconds: segundo, preferredTimescale: 600))
        guard let jpg = NSBitmapImageRep(cgImage: imagen).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return jpg
    }
}
