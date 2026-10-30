import Foundation

/// One of the first four weekly payments of a credit.
struct Pago: Equatable {
    let num: Int
    let fecha: Date
}

/// The payment that currently matters for a client, as the web app's `_pagoActual` computes it.
struct PagoActual {
    let pago: Pago
    let marcadoNoPagado: Bool
    /// A missed payment carried over to the date of the next one ("pago muy atrasado").
    let efectivamenteHoy: Bool
}

enum EstadoPago {
    case pagado, noPagado, hoy, pendiente

    var titulo: String {
        switch self {
        case .pagado: return "Pagado"
        case .noPagado: return "No pagado"
        case .hoy: return "Hoy"
        case .pendiente: return "Pendiente"
        }
    }
}

extension Cliente {
    var inicioCredito: Date? { Fecha.dia(fechaCompra) }

    var fechaFin: Date? {
        guard let inicio = inicioCredito, let semanas = semanas.flatMap({ Int($0) }) else { return nil }
        return Fecha.sumar(dias: semanas * 7, a: inicio)
    }

    var semanasRestantes: Int? {
        guard let fin = fechaFin else { return nil }
        let dias = Fecha.dias(desde: Fecha.hoy, hasta: fin)
        return Int((Double(dias) / 7).rounded(.up))
    }

    var pagos: [Pago] {
        guard let inicio = inicioCredito else { return [] }
        return (1...4).map { Pago(num: $0, fecha: Fecha.sumar(dias: $0 * 7, a: inicio)) }
    }

    func estado(de pago: Pago, hoy: Date = Fecha.hoy) -> EstadoPago {
        if pagosMarcadosNoPagado.contains(pago.num) { return .noPagado }
        if pagosConfirmados.contains(pago.num) { return .pagado }
        if Fecha.mismoDia(pago.fecha, hoy) { return .hoy }
        return .pendiente
    }

    func pagoActual(hoy: Date = Fecha.hoy) -> PagoActual? {
        let noPagados = pagosMarcadosNoPagado
        let confirmados = pagosConfirmados
        let lista = pagos
        func siguiente(_ pago: Pago) -> Pago? { lista.first { $0.num == pago.num + 1 } }

        var activo: Pago?
        for pago in lista {
            if confirmados.contains(pago.num) { continue }
            // A payment marked unpaid is skipped once the next payment's date has passed.
            if noPagados.contains(pago.num), let sig = siguiente(pago), hoy > sig.fecha { continue }
            activo = pago
            break
        }
        guard let activo, let inicio = inicioCredito else { return nil }

        // Only valid until the day before the fifth week.
        if hoy >= Fecha.sumar(dias: 35, a: inicio) { return nil }

        let marcado = noPagados.contains(activo.num)
        var efectivamenteHoy = false
        if marcado, let sig = siguiente(activo), Fecha.mismoDia(hoy, sig.fecha) {
            efectivamenteHoy = true
        }
        return PagoActual(pago: activo, marcadoNoPagado: marcado, efectivamenteHoy: efectivamenteHoy)
    }

    func pagoPendienteHoy(hoy: Date = Fecha.hoy) -> Pago? {
        guard let info = pagoActual(hoy: hoy) else { return nil }
        if Fecha.mismoDia(info.pago.fecha, hoy) || info.efectivamenteHoy { return info.pago }
        return nil
    }

    func pagoAtrasado(hoy: Date = Fecha.hoy) -> Pago? {
        guard let info = pagoActual(hoy: hoy), !info.efectivamenteHoy, info.pago.fecha < hoy else { return nil }
        let lista = pagos

        // A payment marked unpaid rests until the next payment's date.
        if info.marcadoNoPagado, let sig = lista.first(where: { $0.num == info.pago.num + 1 }), hoy <= sig.fecha {
            return nil
        }

        // Marked unpaid today: it shows up again tomorrow.
        let noPagados = pagosMarcadosNoPagado
        if !noPagados.isEmpty, noPagados.contains(info.pago.num - 1) {
            let inicioHoy = hoy.timeIntervalSince1970 * 1000
            let marcado = ultimoMarcadoNoPagado
            if marcado >= inicioHoy, marcado < inicioHoy + 86_400_000 { return nil }
        }
        return info.pago
    }

    var pagaHoy: Bool { categoria == .activos && pagoPendienteHoy() != nil }

    /// Today's payment drags a previous unpaid one.
    var pagoHoyConAtraso: Bool { pagoActual()?.efectivamenteHoy == true }

    var pagosPasadosSinConfirmar: [Pago] {
        guard categoria == .activos, let pago = pagoAtrasado() else { return [] }
        return [pago]
    }

    var debeEstarAlCorriente: Bool { pagosMarcadosNoPagado.isEmpty }
}
