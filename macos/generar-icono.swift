// Rasteriza marca/logo.svg en un .iconset con todos los tamaños que pide macOS.
// Uso: swift generar-icono.swift <logo.svg> <salida.iconset>   (luego: iconutil -c icns)
import AppKit

let argumentos = CommandLine.arguments
guard argumentos.count == 3,
      let logo = NSImage(contentsOf: URL(fileURLWithPath: argumentos[1])) else {
    FileHandle.standardError.write("Uso: swift generar-icono.swift <logo.svg> <salida.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let salida = URL(fileURLWithPath: argumentos[2])
try FileManager.default.createDirectory(at: salida, withIntermediateDirectories: true)

// Rejilla de iconos de macOS: el cuerpo ocupa 824 de 1024 px, centrado (margen de 100).
let margen = 100.0 / 1024.0

for base in [16, 32, 128, 256, 512] {
    for escala in [1, 2] {
        let lado = base * escala
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: lado, pixelsHigh: lado,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { exit(1) }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let m = Double(lado) * margen
        logo.draw(in: NSRect(x: m, y: m, width: Double(lado) - 2 * m, height: Double(lado) - 2 * m))
        NSGraphicsContext.restoreGraphicsState()

        let nombre = escala == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: salida.appendingPathComponent(nombre))
    }
}
