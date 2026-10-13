import Foundation

/// Modo sin interfaz, con el mismo subidor que la app (útil para scripts y pruebas):
///   MisLooms subir <archivo.mp4>   sube un video y escribe el enlace en la salida estándar
///   MisLooms reanudar              reanuda las subidas pendientes
/// Usa MISLOOMS_URL y MISLOOMS_TOKEN (o los ajustes de la app) y, opcionalmente,
/// MISLOOMS_ESTADO para cambiar la carpeta donde se guarda el estado de las subidas.
enum LineaDeComandos {
    nonisolated(unsafe) private static var senalInterrupcion: DispatchSourceSignal?

    static func ejecutarSiCorresponde() -> Bool {
        let argumentos = CommandLine.arguments
        guard argumentos.count >= 2, ["subir", "reanudar"].contains(argumentos[1]) else { return false }

        let tarea = Task {
            do {
                let subidor = Subidor(api: try ClienteAPI())
                var estados: [EstadoSubida]
                if argumentos[1] == "subir" {
                    guard argumentos.count >= 3 else { throw ErrorSubida.archivoNoExiste("(falta el archivo)") }
                    estados = [try EstadoSubida.nueva(archivo: URL(fileURLWithPath: argumentos[2]))]
                } else {
                    estados = EstadoSubida.pendientes()
                    if estados.isEmpty { FileHandle.standardError.write(Data("No hay subidas pendientes.\n".utf8)) }
                }
                for estado in estados {
                    let enlace = try await subidor.procesar(estado) { fraccion in
                        FileHandle.standardError.write(Data(String(format: "\r%3.0f %%", fraccion * 100).utf8))
                    }
                    FileHandle.standardError.write(Data("\n".utf8))
                    print(enlace)
                }
                exit(0)
            } catch is CancellationError {
                FileHandle.standardError.write(Data("\nSubida cancelada; se abortó en el servidor.\n".utf8))
                exit(130)
            } catch {
                FileHandle.standardError.write(Data("\nError: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }

        // Ctrl+C cancela la subida limpiamente (la aborta en el servidor y olvida el estado).
        signal(SIGINT, SIG_IGN)
        let alInterrumpir = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        alInterrumpir.setEventHandler { tarea.cancel() }
        alInterrumpir.resume()
        senalInterrupcion = alInterrumpir
        return true
    }
}
