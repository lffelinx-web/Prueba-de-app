import Foundation

/// Marks and releases for the sending tools; each goes through `guardar` like any client edit.
extension Store {
    private func editarVarios(_ ids: [String], _ cambio: (inout Cliente) -> Void) async -> Bool {
        let conjunto = Set(ids)
        var lista = clientes
        for i in lista.indices where conjunto.contains(lista[i].id) { cambio(&lista[i]) }
        return await guardar(lista)
    }

    private static func ponerSubclave(_ campo: String, _ clave: String, _ valor: JSON?, en c: inout Cliente) {
        var mapa = c[campo]?.object ?? [:]
        mapa[clave] = valor
        c[campo] = .object(mapa)
    }

    // MARK: Reminders

    /// Blocks the clients for every reminder type for the configured days.
    func marcarRecordatorioEnviado(_ ids: [String]) async -> Bool {
        let ahora = JSON.number(Envios.ahora())
        return await editarVarios(ids) { Store.ponerSubclave("ultimoEnvioRec", Envios.claveRecordatorio, ahora, en: &$0) }
    }

    func desbloquearRecordatorio(_ ids: [String]) async -> Bool {
        await editarVarios(ids) { Store.ponerSubclave("ultimoEnvioRec", Envios.claveRecordatorio, nil, en: &$0) }
    }

    // MARK: Messages

    /// `_marcarComoEnviados`: blocks the contacts in every message list, and in reminders through `_global`.
    func marcarMensajeEnviado(_ ids: [String], categoria: CategoriaMensaje, cuerpo: CuerpoMensaje?) async -> Bool {
        let ahora = JSON.number(Envios.ahora())
        return await editarVarios(ids) { c in
            c["ultimoEnvioMasivo"] = ahora
            if categoria == .sinrenovar, let cuerpo {
                Store.ponerSubclave("ultimoEnvioSinRenovar", cuerpo.rawValue, ahora, en: &c)
                if cuerpo == .macropesos { Store.ponerSubclave("ultimoEnvioSinRenovar", CuerpoMensaje.linea.rawValue, ahora, en: &c) }
            }
            Store.ponerSubclave("ultimoEnvioRec", "_global", ahora, en: &c)
        }
    }

    func desmarcarMensaje(_ ids: [String]) async -> Bool {
        await editarVarios(ids) { c in
            c["ultimoEnvioMasivo"] = nil
            c["ultimoEnvioSinRenovar"] = nil
            if c["ultimoEnvioRec"]?.object != nil { Store.ponerSubclave("ultimoEnvioRec", "_global", nil, en: &c) }
        }
    }

    // MARK: Credit line for "sin renovar"

    func guardarLinea(_ id: String, monto: String) async -> Bool {
        await editarVarios([id]) { $0["lineaCreditoGuardada"] = .string(monto) }
    }

    /// A $0 line hides the client from the "línea de crédito" list for 21 days.
    func suspenderLinea(_ id: String) async -> Bool {
        let hasta = JSON.number(Envios.ahora() + 21 * Envios.dia)
        return await editarVarios([id]) { c in
            c["suspendidoLineaSinRenovar"] = hasta
            c["lineaCreditoGuardada"] = nil
        }
    }
}
