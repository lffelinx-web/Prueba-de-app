import Foundation

/// Business rules over the whole client list, ported from the web app.
enum Reglas {
    // MARK: - Double financing

    /// The older credit (earlier purchase date, then lower SL) is the secondary one.
    static func esCreditoSecundario(_ c: Cliente, respectoA otro: Cliente) -> Bool {
        let fa = c.fechaCompra ?? "", fb = otro.fechaCompra ?? ""
        if fa != fb { return fa < fb }
        return (c.sl ?? "").uppercased() < (otro.sl ?? "").uppercased()
    }

    /// Hidden from the active list because its linked credit shows instead.
    static func ocultoPorDobleFin(_ c: Cliente, en clientes: [Cliente]) -> Bool {
        guard let otroId = c.dobleFinId, let otro = clientes.first(where: { $0.id == otroId }),
              otro.categoria == .activos || otro.categoria == .sinrenovar else { return false }
        return esCreditoSecundario(c, respectoA: otro)
    }

    static func entradaHistorial(de c: Cliente, fechaFin: String?) -> JSON {
        .object([
            "sl": .from(c.sl),
            "fechaCompra": .from(c.fechaCompra),
            "semanas": c["semanas"] ?? .null,
            "asesor": .from(c.asesor),
            "tipo": .from(c.tipo),
            "fechaFin": .from(fechaFin),
            "pagosConfirmados": .from(c.pagosConfirmados),
            "estatus": "liquidado",
            "refs": .array(c.refs.map(\.json)),
        ])
    }

    /// Moves `c` into the history of its still-active linked credit. Returns false if there is none.
    static func archivarEnCreditoVinculado(_ c: Cliente, en clientes: inout [Cliente]) -> Bool {
        guard let otroId = c.dobleFinId,
              let otro = clientes.firstIndex(where: { $0.id == otroId && $0.categoria == .activos }) else { return false }
        var historial = clientes[otro].historial
        historial.append(entradaHistorial(de: c, fechaFin: c.fechaFin.map(Fecha.iso)))
        clientes[otro]["historial"] = .array(historial)
        clientes[otro].dobleFinId = nil
        clientes.removeAll { $0.id == c.id }
        return true
    }

    // MARK: - PR attached to "sin renovar"

    /// Approved PRs last 28 days, rejected ones 90.
    static func prAdjuntaActiva(_ c: Cliente, hoy: Date = Fecha.hoy) -> [String: JSON]? {
        guard let pr = c.prActual else { return nil }
        guard let base = Fecha.dia(pr["fechaSolicitud"]?.text) ?? Fecha.dia(pr["fechaIngresoPR"]?.text) else { return nil }
        let limite = pr["estatus"]?.text == "aprobada" ? 28 : 90
        return Fecha.dias(desde: base, hasta: hoy) < limite ? pr : nil
    }

    static func diasRestantesPRAdjunta(_ pr: [String: JSON]) -> Int {
        let base = Fecha.dia(pr["fechaSolicitud"]?.text) ?? Fecha.dia(pr["fechaIngresoPR"]?.text)
        let limite = pr["estatus"]?.text == "aprobada" ? 28 : 90
        let dias = base.map { Fecha.dias(desde: $0, hasta: Fecha.hoy) } ?? 0
        return max(0, limite - dias)
    }

    // MARK: - Automatic maintenance (administrator only)

    struct NotificacionNueva {
        let tipo: String
        let datos: [String: JSON]
    }

    /// Runs `checkVencidos`, `checkPRExpiry` and `_limpiarPRsExpiradas` on a copy of the list.
    static func mantenimiento(_ entrada: [Cliente], hoy: Date = Fecha.hoy) -> (clientes: [Cliente], notificaciones: [NotificacionNueva]) {
        var clientes = entrada
        var avisos: [NotificacionNueva] = []

        // A "sin renovar" credit linked to an active one belongs in that credit's history.
        for c in clientes where c.categoria == .sinrenovar && c.dobleFinId != nil {
            _ = archivarEnCreditoVinculado(c, en: &clientes)
        }

        // Finished credits: archive double financing, otherwise ask for confirmation.
        for c in clientes where c.categoria == .activos {
            guard let fin = c.fechaFin, Date() >= Fecha.calendario.date(bySettingHour: 12, minute: 0, second: 0, of: fin) ?? fin else { continue }
            if archivarEnCreditoVinculado(c, en: &clientes) { continue }
            if c.estatus == .atraso { continue }
            avisos.append(NotificacionNueva(tipo: "vencido_a_sinrenovar", datos: [
                "clienteId": .string(c.id),
                "nombre": .string(c.nombre),
                "sl": .string(c.sl ?? ""),
                "fechaFin": .string(Fecha.iso(fin)),
                "mensaje": .string("El crédito de \(c.nombre) (\(c.sl ?? "sin SL")) ya finalizó. ¿Confirmas que pasa a Sin renovar?"),
            ]))
        }

        // PRs expire into prospects: approved after 30 days, rejected after 90.
        for i in clientes.indices {
            let c = clientes[i]
            guard c.categoria?.esPR == true, let base = c.fechaSolicitud ?? c.fechaIngresoPR, let inicio = Fecha.dia(base) else { continue }
            let dias = Fecha.dias(desde: inicio, hasta: hoy)
            if c.categoria == .prAprobadas, dias >= 30 {
                avisos.append(NotificacionNueva(tipo: "pr_a_prospecto", datos: [
                    "clienteId": .string(c.id),
                    "nombre": .string(c.nombre),
                    "sl": .string(c.sl ?? c.numPR ?? ""),
                    "categoria": "pr-aprobadas",
                    "mensaje": .string("La PR aprobada de \(c.nombre) pasó a prospecto (30 días sin movimiento)"),
                ]))
                clientes[i].categoria = .prospectos
                clientes[i].origen = "Fue PR aprobada"
                clientes[i].fechaRef = base
                clientes[i]["esPRAprobada"] = true
            } else if c.categoria == .prRechazadas, dias >= 90 {
                clientes[i].categoria = .prospectos
                clientes[i].origen = "Fue PR rechazada"
                clientes[i].fechaRef = base
            }
        }

        // Expired attached PRs, or ones whose PR record is gone, move to `historialPR`.
        for i in clientes.indices where clientes[i].categoria == .sinrenovar {
            guard let pr = clientes[i].prActual else { continue }
            var vigente = prAdjuntaActiva(clientes[i], hoy: hoy) != nil
            if let prId = pr["clientePRId"]?.text {
                let registro = clientes.first { $0.id == prId }
                if registro?.categoria?.esPR != true { vigente = false }
            }
            if !vigente {
                var archivada = pr
                archivada["fechaExpiracion"] = .string(Fecha.iso(hoy))
                var historialPR = clientes[i]["historialPR"]?.list ?? []
                historialPR.append(.object(archivada))
                clientes[i]["historialPR"] = .array(historialPR)
                clientes[i]["prActual"] = nil
            }
        }
        return (clientes, avisos)
    }

    // MARK: - Dashboard

    struct PagoCliente: Identifiable {
        let cliente: Cliente
        let pago: Pago
        var id: String { cliente.id }
    }

    static func pagosHoy(_ clientes: [Cliente]) -> [PagoCliente] {
        clientes.compactMap { c -> PagoCliente? in
            guard c.categoria == .activos, let pago = c.pagoPendienteHoy() else { return nil }
            return PagoCliente(cliente: c, pago: pago)
        }
        .sorted { $0.pago.num < $1.pago.num }
    }

    /// Approved PRs remind every 7 days from the request.
    static func prPendientes(_ clientes: [Cliente]) -> [Cliente] {
        let hoy = Fecha.hoy
        return clientes.filter { c in
            guard c.categoria == .prAprobadas else { return false }
            guard let base = Fecha.dia(c.fechaSolicitud ?? c.fechaIngresoPR) else { return true }
            let dias = Fecha.dias(desde: base, hasta: hoy)
            return dias >= 0 && dias % 7 == 0
        }
    }

    /// Credits ending this week, Monday to Sunday.
    static func liquidacionesSemana(_ clientes: [Cliente]) -> [Cliente] {
        let hoy = Fecha.hoy
        let diaSemana = Fecha.calendario.component(.weekday, from: hoy) // 1 = domingo
        let desdeLunes = diaSemana == 1 ? 6 : diaSemana - 2
        let lunes = Fecha.sumar(dias: -desdeLunes, a: hoy)
        let domingo = Fecha.sumar(dias: 6, a: lunes)
        return clientes.filter { c in
            guard c.categoria == .activos, let fin = c.fechaFin else { return false }
            return fin >= lunes && fin <= domingo
        }
    }

    static func enSeguimiento(_ clientes: [Cliente]) -> [Cliente] {
        clientes.filter { $0.seguimiento != nil && $0.categoria != .fraude }
    }

    static func atrasados(_ clientes: [Cliente]) -> [PagoCliente] {
        clientes.compactMap { c -> PagoCliente? in
            guard c.categoria == .activos, let pago = c.pagoAtrasado() else { return nil }
            return PagoCliente(cliente: c, pago: pago)
        }
    }

    // MARK: - Database lists

    static func conteo(_ categoria: Categoria, en clientes: [Cliente]) -> Int {
        switch categoria {
        case .activos:
            return clientes.filter { $0.categoria == .activos && !ocultoActivo($0, en: clientes) }.count
        case .prospectos:
            return clientes.filter { $0.categoria == .prospectos && !$0.inhabilitado }.count
        case .fraude:
            return clientes.filter { $0.categoria == .fraude && $0.refDeId == nil }.count
        default:
            return clientes.filter { $0.categoria == categoria }.count
        }
    }

    private static func ocultoActivo(_ c: Cliente, en clientes: [Cliente]) -> Bool {
        guard let otroId = c.dobleFinId, let otro = clientes.first(where: { $0.id == otroId && $0.categoria == .activos }) else { return false }
        return esCreditoSecundario(c, respectoA: otro)
    }

    static func ordenar(_ lista: [Cliente], _ categoria: Categoria) -> [Cliente] {
        switch categoria {
        case .prAprobadas, .prRechazadas:
            return lista.sorted { ($0.numPR ?? "") > ($1.numPR ?? "") }
        case .prospectos:
            return lista.sorted { ($0.fechaRef ?? "") > ($1.fechaRef ?? "") }
        default:
            return lista.sorted { ($0.fechaCompra ?? "") > ($1.fechaCompra ?? "") }
        }
    }

    static func lista(_ categoria: Categoria, en clientes: [Cliente], busqueda: String, filtros: Filtros) -> [Cliente] {
        let q = busqueda.lowercased()
        let visibles = clientes.filter { c in
            guard c.categoria == categoria else { return false }
            switch categoria {
            case .activos: if ocultoPorDobleFin(c, en: clientes) { return false }
            case .fraude: if c.refDeId != nil { return false }
            default: break
            }
            guard !q.isEmpty else { return true }
            return c.nombre.lowercased().contains(q) || c.tel.contains(q)
                || (c.sl ?? "").lowercased().contains(q) || (c.numPR ?? "").lowercased().contains(q)
        }
        return ordenar(visibles.filter { filtros.acepta($0, categoria: categoria) }, categoria)
    }

    struct Duplicado: Identifiable {
        let a: Cliente
        let b: Cliente
        let mismoNombre: Bool
        let mismoTel: Bool
        var id: String { a.id + "|" + b.id }

        var mensaje: String {
            if mismoNombre && mismoTel { return "Nombre y teléfono iguales: \(a.nombre) (\(a.tel))" }
            if mismoNombre { return "Nombre igual (tel. diferente): \(a.nombre)" }
            return "Teléfono igual (nombre diferente): \(a.tel)"
        }
    }

    /// Possible duplicates inside a category. Active clients handle this when saving instead.
    static func duplicados(_ categoria: Categoria, en clientes: [Cliente]) -> [Duplicado] {
        guard categoria != .activos else { return [] }
        let lista = clientes.filter { $0.categoria == categoria && !$0.inhabilitado }
        var pares: [Duplicado] = []
        for i in lista.indices {
            for j in lista.indices where j > i {
                let a = lista[i], b = lista[j]
                let nombre = !a.nombre.isEmpty && !b.nombre.isEmpty
                    && a.nombre.trimmingCharacters(in: .whitespaces).lowercased() == b.nombre.trimmingCharacters(in: .whitespaces).lowercased()
                let tel = !a.tel.isEmpty && a.tel == b.tel
                if nombre || tel { pares.append(Duplicado(a: a, b: b, mismoNombre: nombre, mismoTel: tel)) }
            }
        }
        return pares
    }
}

/// The filter panel of a database category. Empty strings mean "any".
struct Filtros: Equatable {
    var asesor = ""
    var tipo = ""          // Compra / Préstamo
    var plazo = ""
    var estatus = ""
    var compraDesde: Date?
    var compraHasta: Date?
    var venceDesde: Date?
    var venceHasta: Date?
    var macroMin = ""
    var macroMax = ""
    var tipoProspecto = "" // pr-aprobada / normal
    var verificado = ""    // si / no
    var whatsapp = ""      // si / no
    var tipocred = ""      // Financing / Créditos
    var fechaDesde: Date?
    var fechaHasta: Date?

    static let filtrables: Set<Categoria> = [.activos, .sinrenovar, .prospectos, .prAprobadas]

    var cantidad: Int {
        let textos = [asesor, tipo, plazo, estatus, macroMin, macroMax, tipoProspecto, verificado, whatsapp, tipocred]
        let fechas = [compraDesde, compraHasta, venceDesde, venceHasta, fechaDesde, fechaHasta]
        return textos.filter { !$0.isEmpty }.count + fechas.compactMap { $0 }.count
    }

    func acepta(_ c: Cliente, categoria: Categoria) -> Bool {
        guard Filtros.filtrables.contains(categoria) else { return true }
        func iso(_ d: Date?) -> String? { d.map(Fecha.iso) }

        if !asesor.isEmpty, (c.asesor ?? "") != asesor { return false }
        switch categoria {
        case .prospectos:
            if tipoProspecto == "pr-aprobada", !c.esPRAprobada { return false }
            if tipoProspecto == "normal", c.esPRAprobada { return false }
            if let desde = iso(fechaDesde), (c.fechaRef ?? "") < desde { return false }
            if let hasta = iso(fechaHasta), (c.fechaRef ?? "") > hasta { return false }
            if !verificado.isEmpty, (verificado == "si") != c.verificado { return false }
            if !whatsapp.isEmpty, (whatsapp == "si") != c.tieneWA { return false }
            return true
        case .prAprobadas:
            if !tipocred.isEmpty, (c.tipocred ?? "") != tipocred { return false }
            if let desde = iso(fechaDesde), (c.fechaSolicitud ?? "") < desde { return false }
            if let hasta = iso(fechaHasta), (c.fechaSolicitud ?? "") > hasta { return false }
            return true
        default:
            if !tipo.isEmpty, (c.tipo ?? "") != tipo { return false }
            if !plazo.isEmpty, (c.semanas ?? "") != plazo { return false }
            if !estatus.isEmpty, c.estatusTexto != estatus { return false }
            if let desde = iso(compraDesde), (c.fechaCompra ?? "") < desde { return false }
            if let hasta = iso(compraHasta), (c.fechaCompra ?? "") > hasta { return false }
            if venceDesde != nil || venceHasta != nil {
                let fin = c.fechaFin.map(Fecha.iso) ?? ""
                if let desde = iso(venceDesde), fin < desde { return false }
                if let hasta = iso(venceHasta), fin > hasta { return false }
            }
            let macro = c.macropesos ?? 0
            if let minimo = Double(macroMin), macro < minimo { return false }
            if let maximo = Double(macroMax), macro > maximo { return false }
            return true
        }
    }
}

enum Catalogos {
    static let plazos = ["6", "13", "26", "36", "39", "52", "78", "104", "125"]
    static let tiposCredito = ["Compra", "Préstamo"]
    static let tiposPR = ["Financing", "Créditos"]
}
