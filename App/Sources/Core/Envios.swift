import Foundation

/// Who appears in each sending list and who is blocked because they were contacted recently,
/// ported from the web app's reminder and mass-message tools.
enum Envios {
    static let dia: Double = 86_400_000

    /// Blocking days per category, set by the administrator (7 by default).
    struct DiasBloqueo: Equatable {
        var valores: [String: Int] = [:]

        func dias(_ clave: String) -> Int { valores[clave] ?? 7 }
        func ms(_ clave: String) -> Double { Double(dias(clave)) * Envios.dia }

        static let categorias = ["activos", "sinrenovar", "prospectos", "porfinalizar", "pr-aprobadas"]
    }

    static func ahora() -> Double { Double(Fecha.milisegundos()) }

    // MARK: Reminders (active clients)

    /// Every reminder type shares one block key, so one reminder blocks all of them.
    static let claveRecordatorio = "activos-rec"

    static func ultimoRecordatorio(_ c: Cliente) -> Double {
        c["ultimoEnvioRec"]?[claveRecordatorio]?.number ?? 0
    }

    static func recordatorioBloqueado(_ c: Cliente, dias: DiasBloqueo, ahora: Double = ahora()) -> Bool {
        let ultimo = ultimoRecordatorio(c)
        return ultimo > 0 && ahora - ultimo < dias.ms("activos")
    }

    /// One entry per person (CURP, then phone, then name + SL), keeping the main credit of a double financing.
    static func unoPorPersona(_ lista: [Cliente]) -> [Cliente] {
        var orden: [String] = []
        var porClave: [String: Cliente] = [:]
        for c in lista {
            let curp = (c.curp ?? "").trimmingCharacters(in: .whitespaces)
            let tel = c.tel.trimmingCharacters(in: .whitespaces)
            let clave = !curp.isEmpty ? curp : (!tel.isEmpty ? tel : c.nombre.lowercased().trimmingCharacters(in: .whitespaces) + "|" + (c.sl ?? ""))
            if let previo = porClave[clave] {
                if previo.dobleFinId != nil, Reglas.esCreditoSecundario(previo, respectoA: c) { porClave[clave] = c }
            } else {
                orden.append(clave)
                porClave[clave] = c
            }
        }
        return orden.compactMap { porClave[$0] }
    }

    private static func activoAlCorrienteConWhatsApp(_ c: Cliente) -> Bool {
        c.categoria == .activos && c.estatus == .alCorriente && c.tieneWA && !c.tel.isEmpty && !c.suspendido
    }

    /// Paid more than half and more than 6 weeks left.
    static func mitadPagadaConSemanas(_ c: Cliente) -> Bool {
        guard let inicio = c.inicioCredito, let total = c.semanas.flatMap({ Int($0) }), total > 0,
              let restantes = c.semanasRestantes else { return false }
        let transcurridas = Fecha.dias(desde: inicio, hasta: Fecha.hoy) / 7
        return Double(transcurridas) > Double(total) / 2 && restantes > 6
    }

    static func candidatosRecordatorio(_ tipo: TipoRecordatorio, en clientes: [Cliente], macroMinimo: Double = 0) -> [Cliente] {
        let ahora = ahora()
        let lista: [Cliente]
        switch tipo {
        case .macropesosDisponibles:
            lista = clientes.filter { c in
                let macro = c.macropesos ?? 0
                return activoAlCorrienteConWhatsApp(c) && macro >= macroMinimo && macro > 0
            }
        case .macropesosInvitacion:
            lista = clientes.filter(activoAlCorrienteConWhatsApp)
        case .creditoDisponible:
            lista = clientes.filter { c in
                guard activoAlCorrienteConWhatsApp(c), normalizarNombre(c.tipo) != "prestamo" else { return false }
                // Already has a second active credit.
                if let otro = c.dobleFinId, clientes.contains(where: { $0.id == otro && $0.categoria == .activos }) { return false }
                if let hasta = c["suspendidoCreditoDisp"]?.number, ahora < hasta { return false }
                return mitadPagadaConSemanas(c)
            }
        case .pagosHoy, .pagosAtrasados:
            lista = []
        }
        return unoPorPersona(lista).sorted { $0.nombre.localizedCompare($1.nombre) == .orderedAscending }
    }

    // MARK: Messages

    /// Latest mass or "sin renovar" message, which blocks the contact in every message list.
    static func ultimoMensaje(_ c: Cliente) -> Double {
        var marcas: [Double] = []
        if let masivo = c["ultimoEnvioMasivo"]?.number { marcas.append(masivo) }
        for valor in (c["ultimoEnvioSinRenovar"]?.object ?? [:]).values {
            if case .number(let ts) = valor { marcas.append(ts) }
        }
        return marcas.max() ?? 0
    }

    static func mensajeBloqueado(_ c: Cliente, categoria: CategoriaMensaje, dias: DiasBloqueo, ahora: Double = ahora()) -> Bool {
        ahora - ultimoMensaje(c) < dias.ms(categoria.claveBloqueo)
    }

    static func porFinalizar(_ c: Cliente, en clientes: [Cliente]) -> Bool {
        guard c.categoria == .activos, c.estatus != .atraso, normalizarNombre(c.tipo) != "prestamo", let fin = c.fechaFin else { return false }
        let hoy = Fecha.hoy
        guard fin >= hoy, fin <= Fecha.sumar(dias: 35, a: hoy) else { return false }
        if let otro = c.dobleFinId, clientes.contains(where: { $0.id == otro && $0.categoria == .activos }) { return false }
        return true
    }

    /// The contacts of a message list, in random order, and how many were left out as blocked.
    static func lista(_ categoria: CategoriaMensaje, cuerpo: CuerpoMensaje, en clientes: [Cliente], dias: DiasBloqueo) -> (contactos: [Cliente], bloqueados: Int) {
        let enAtraso = Set(clientes.filter { $0.estatus == .atraso }.map(\.id))
        var base: [Cliente]
        switch categoria {
        case .porfinalizar:
            base = clientes.filter { porFinalizar($0, en: clientes) }
        case .sinrenovar:
            base = clientes.filter { $0.categoria == .sinrenovar && $0.estatus != .atraso && Reglas.prAdjuntaActiva($0) == nil && !$0.suspendido }
            if cuerpo == .macropesos { base = base.filter { ($0.macropesos ?? 0) > 1 } }
            if cuerpo == .linea {
                let ahora = ahora()
                base = base.filter { c in (c["suspendidoLineaSinRenovar"]?.number).map { ahora >= $0 } ?? true }
            }
        case .prospectos:
            base = clientes.filter { $0.categoria == .prospectos && !$0.inhabilitado && $0.estatus != .atraso && !enAtraso.contains($0.refDeId ?? "") }
        case .prospectosVerificados:
            base = clientes.filter { $0.categoria == .prospectos && !$0.inhabilitado && $0.verificado && $0.estatus != .atraso }
        case .prAprobadas:
            base = clientes.filter { $0.categoria == .prAprobadas && $0.estatus != .atraso }
        }
        base = base.filter { $0.tieneWA && !$0.tel.isEmpty && !$0.suspendido }

        var telefonos = Set<String>()
        base = base.filter { telefonos.insert($0.tel).inserted }

        let ahora = ahora()
        let disponibles = base.filter { !mensajeBloqueado($0, categoria: categoria, dias: dias, ahora: ahora) }
        return (disponibles.shuffled(), base.count - disponibles.count)
    }

    /// Recently messaged contacts of a category, newest first, to release them early.
    static func bloqueados(_ categoria: CategoriaMensaje, en clientes: [Cliente], dias: DiasBloqueo) -> [Cliente] {
        let ahora = ahora()
        return clientes.filter { c in
            guard c.tieneWA, !c.tel.isEmpty, ultimoMensaje(c) > 0, mensajeBloqueado(c, categoria: categoria, dias: dias, ahora: ahora) else { return false }
            switch categoria {
            case .porfinalizar: return c.categoria == .activos
            case .sinrenovar: return c.categoria == .sinrenovar
            case .prospectos, .prospectosVerificados: return c.categoria == .prospectos && !c.inhabilitado
            case .prAprobadas: return c.categoria == .prAprobadas
            }
        }
        .sorted { ultimoMensaje($0) > ultimoMensaje($1) }
    }

    // MARK: Payments by day

    struct PagoDelDia: Identifiable {
        let cliente: Cliente
        let numero: Int
        let total: Int
        var id: String { cliente.id + "-\(numero)" }
        var porcentaje: Int { Int((Double(numero) / Double(max(total, 1)) * 100).rounded()) }
    }

    /// Payments of up-to-date active clients falling on a day (`desplazamiento` -1 = ayer, 1 = mañana),
    /// furthest along first.
    static func pagos(enDia desplazamiento: Int, de clientes: [Cliente]) -> [PagoDelDia] {
        let objetivo = Fecha.sumar(dias: desplazamiento, a: Fecha.hoy)
        var resultado: [PagoDelDia] = []
        for c in clientes where c.categoria == .activos && c.estatus == .alCorriente {
            guard let inicio = c.inicioCredito, let total = c.semanas.flatMap({ Int($0) }), total > 0 else { continue }
            let dias = Fecha.dias(desde: inicio, hasta: objetivo)
            guard dias > 0, dias % 7 == 0, dias / 7 <= total else { continue }
            resultado.append(PagoDelDia(cliente: c, numero: dias / 7, total: total))
        }
        return resultado.sorted {
            let a = Double($0.numero) / Double($0.total), b = Double($1.numero) / Double($1.total)
            return a != b ? a > b : $0.cliente.nombre.localizedCompare($1.cliente.nombre) == .orderedAscending
        }
    }

    // MARK: Export

    /// CSV with the first name and phone, as the web exports it (UTF-8 with BOM for Excel).
    static func csv(_ contactos: [Cliente]) -> String {
        func celda(_ texto: String) -> String { "\"" + texto.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let filas = [["Name", "Phone"]] + contactos.map { [Mensajes.primerNombre($0.nombre), $0.tel] }
        return "\u{FEFF}" + filas.map { $0.map(celda).joined(separator: ",") }.joined(separator: "\n")
    }
}
