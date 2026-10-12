import Carbon.HIToolbox

/// Atajos globales vía Carbon: no requieren permiso de Accesibilidad.
final class AtajoGlobal {
    private static var acciones: [UInt32: () -> Void] = [:]
    private static var manejador: EventHandlerRef?
    private static var siguienteId: UInt32 = 1

    private var referencia: EventHotKeyRef?

    /// - Parameters:
    ///   - tecla: código virtual, p. ej. `kVK_ANSI_L`.
    ///   - modificadores: máscara Carbon (`cmdKey`, `optionKey`, `shiftKey`, `controlKey`).
    init(tecla: Int, modificadores: Int, accion: @escaping () -> Void) {
        Self.instalarManejador()
        let id = Self.siguienteId
        Self.siguienteId += 1
        Self.acciones[id] = accion
        RegisterEventHotKey(UInt32(tecla), UInt32(modificadores),
                            EventHotKeyID(signature: OSType(0x4D4C4F4D) /* 'MLOM' */, id: id),
                            GetApplicationEventTarget(), 0, &referencia)
    }

    deinit {
        if let referencia { UnregisterEventHotKey(referencia) }
    }

    /// Un único manejador de eventos para todos los atajos; distingue por id.
    private static func instalarManejador() {
        guard manejador == nil else { return }
        var tipo = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, evento, _ in
            var id = EventHotKeyID()
            GetEventParameter(evento, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            DispatchQueue.main.async { AtajoGlobal.acciones[id.id]?() }
            return noErr
        }, 1, &tipo, nil, &manejador)
    }
}
