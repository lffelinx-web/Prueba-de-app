import Foundation

/// Client actions. Each one edits a copy of the list and hands it to `guardar`.
extension Store {
    private func editar(_ cambio: (inout [Cliente]) -> Void) async -> Bool {
        var lista = clientes
        cambio(&lista)
        return await guardar(lista)
    }

    private func indice(_ id: String, en lista: [Cliente]) -> Int? {
        lista.firstIndex { $0.id == id }
    }

    /// Changes a client's status and carries it to the prospects created from its references.
    static func ponerEstatus(_ estatus: Estatus, a id: String, en lista: inout [Cliente]) {
        guard let i = lista.firstIndex(where: { $0.id == id }), lista[i].estatus != estatus else { return }
        lista[i].estatusTexto = estatus.rawValue
        for j in lista.indices where lista[j].refDeId == id {
            if estatus == .atraso, lista[j].categoria == .prospectos { lista[j].estatusTexto = Estatus.atraso.rawValue }
            if estatus == .alCorriente { lista[j].estatusTexto = Estatus.alCorriente.rawValue }
        }
    }

    // MARK: - Payments

    func confirmarPagos(_ numeros: [Int], de id: String) async {
        _ = await editar { lista in
            guard let i = self.indice(id, en: lista) else { return }
            var confirmados = lista[i].pagosConfirmados
            for num in numeros where !confirmados.contains(num) { confirmados.append(num) }
            lista[i].pagosConfirmados = confirmados
            lista[i].pagosMarcadosNoPagado = lista[i].pagosMarcadosNoPagado.filter { !numeros.contains($0) }
            if lista[i].estatus == .atraso, lista[i].debeEstarAlCorriente {
                Store.ponerEstatus(.alCorriente, a: id, en: &lista)
            }
        }
    }

    func marcarNoPagado(_ num: Int, de id: String) async {
        _ = await editar { lista in
            guard let i = self.indice(id, en: lista) else { return }
            var marcados = lista[i].pagosMarcadosNoPagado
            if !marcados.contains(num) { marcados.append(num) }
            lista[i].pagosMarcadosNoPagado = marcados
            // Keeps the next payment out of "atrasados" until tomorrow.
            lista[i]["ultimoMarcadoNoPagado"] = .number(Double(Fecha.milisegundos()))
            lista[i].pagosConfirmados = lista[i].pagosConfirmados.filter { $0 != num }
            if lista[i].estatus != .fraude {
                Store.ponerEstatus(.atraso, a: id, en: &lista)
            }
        }
    }

    /// Back to pending from either "pagado" or "no pagado".
    func revertirPago(_ num: Int, de id: String) async {
        _ = await editar { lista in
            guard let i = self.indice(id, en: lista) else { return }
            lista[i].pagosConfirmados = lista[i].pagosConfirmados.filter { $0 != num }
            lista[i].pagosMarcadosNoPagado = lista[i].pagosMarcadosNoPagado.filter { $0 != num }
        }
    }

    // MARK: - Status

    func cambiarEstatus(de id: String, a nuevo: Estatus) async {
        guard let actual = cliente(id), actual.estatus != nuevo else { return }
        let anterior = actual.estatus
        _ = await editar { lista in
            guard let i = self.indice(id, en: lista) else { return }
            if nuevo == .fraude {
                lista[i].categoria = .fraude
                lista[i].estatusTexto = Estatus.fraude.rawValue
                for j in lista.indices where lista[j].refDeId == id && lista[j].categoria == .prospectos {
                    lista[j].categoria = .fraude
                    lista[j].estatusTexto = Estatus.fraude.rawValue
                }
            } else if nuevo == .alCorriente, lista[i].categoria == .fraude {
                lista[i].categoria = .activos
                lista[i].estatusTexto = Estatus.alCorriente.rawValue
                for j in lista.indices where lista[j].refDeId == id && lista[j].categoria == .fraude {
                    lista[j].categoria = .prospectos
                    lista[j].estatusTexto = Estatus.alCorriente.rawValue
                }
            } else {
                lista[i].estatusTexto = nuevo.rawValue
                if anterior == .atraso {
                    for j in lista.indices where lista[j].refDeId == id { lista[j].estatusTexto = Estatus.alCorriente.rawValue }
                }
                if nuevo == .atraso {
                    for j in lista.indices where lista[j].refDeId == id && lista[j].categoria == .prospectos {
                        lista[j].estatusTexto = Estatus.atraso.rawValue
                    }
                }
            }
        }
    }

    // MARK: - Follow-up, macropesos, suspension

    func guardarSeguimiento(_ id: String, tipo: String, notas: String) async -> Bool {
        await editar { lista in
            guard let i = self.indice(id, en: lista) else { return }
            lista[i].seguimiento = Seguimiento(tipo: tipo, notas: Texto.limpio(notas), fecha: Fecha.hoyISO)
        }
    }

    func quitarSeguimiento(_ id: String) async {
        _ = await editar { lista in
            guard let i = self.indice(id, en: lista) else { return }
            lista[i].seguimiento = nil
        }
    }

    func guardarMacropesos(_ id: String, valor: Double?) async {
        if let valor, !valor.isFinite || valor < 0 {
            avisar("Ingresa macropesos válidos: cero o un número positivo.", advertencia: true)
            return
        }
        _ = await editar { lista in
            guard let i = self.indice(id, en: lista) else { return }
            let anterior = lista[i].macropesos
            lista[i]["macropesos"] = valor.map(JSON.number) ?? .string("")
            if anterior != valor {
                lista[i]["macropesosFechaActualizacion"] = .string(Fecha.timestampISO())
            }
        }
    }

    func alternarSuspension(_ id: String) async {
        _ = await editar { lista in
            guard let i = self.indice(id, en: lista) else { return }
            lista[i]["suspendido"] = .bool(!lista[i].suspendido)
        }
    }

    // MARK: - Deleting and moving

    /// Deleting an active, "sin renovar" or fraud client also deletes the prospects created
    /// from its references, and unlinks a double-financing partner.
    func eliminar(_ id: String) async {
        guard let objetivo = cliente(id) else { return }
        _ = await editar { lista in
            if let otro = objetivo.dobleFinId, let j = self.indice(otro, en: lista) {
                lista[j].dobleFinId = nil
            }
            if [.activos, .sinrenovar, .fraude].contains(objetivo.categoria) {
                lista.removeAll { $0.refDeId == id }
            }
            lista.removeAll { $0.id == id }
        }
    }

    func tieneReferenciasVinculadas(_ id: String) -> Bool {
        clientes.contains { $0.refDeId == id }
    }

    func liquidacionAnticipada(_ id: String) async {
        guard let c = cliente(id) else { return }
        _ = await editar { lista in
            if Reglas.archivarEnCreditoVinculado(c, en: &lista) { return }
            guard let i = self.indice(id, en: lista) else { return }
            lista[i].categoria = .sinrenovar
        }
    }

    /// From the "crédito finalizado" notification.
    func confirmarPaseSinRenovar(notificacion: String, clienteId: String) async {
        guard let c = cliente(clienteId) else {
            avisar("Cliente no encontrado", advertencia: true)
            eliminarNotificacion(notificacion)
            return
        }
        let ok = await editar { lista in
            if Reglas.archivarEnCreditoVinculado(c, en: &lista) { return }
            guard let i = self.indice(clienteId, en: lista) else { return }
            lista[i].categoria = .sinrenovar
        }
        if ok { eliminarNotificacion(notificacion) }
    }

    /// Removes the PR attached to a "sin renovar" client, and its PR record.
    func eliminarPRAdjunta(_ id: String) async {
        _ = await editar { lista in
            guard let i = self.indice(id, en: lista), var pr = lista[i].prActual else { return }
            if let prId = pr["clientePRId"]?.text { lista.removeAll { $0.id == prId } }
            guard let k = self.indice(id, en: lista) else { return }
            pr["fechaEliminacion"] = .string(Fecha.hoyISO)
            pr["eliminadaManualmente"] = true
            var historial = lista[k]["historialPR"]?.list ?? []
            historial.append(.object(pr))
            lista[k]["historialPR"] = .array(historial)
            lista[k]["prActual"] = nil
        }
    }

    func cambiarInhabilitado(_ id: String, _ inhabilitado: Bool) async {
        _ = await editar { lista in
            guard let i = self.indice(id, en: lista) else { return }
            lista[i]["inhabilitado"] = .bool(inhabilitado)
        }
    }
}

enum Texto {
    /// The web app's `sanitizarInput`: strips markup that could become script.
    static func limpio(_ texto: String) -> String {
        var salida = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        for patron in ["<script", "</script", "javascript:", "<iframe", "<object", "<embed", "<link", "<meta"] {
            salida = salida.replacingOccurrences(of: patron, with: "", options: .caseInsensitive)
        }
        return salida.replacingOccurrences(of: #"on\w+="#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    /// Same cleanup without trimming, for template parts like "Hola, " whose spaces matter.
    static func limpioConEspacios(_ texto: String) -> String {
        var salida = texto
        for patron in ["<script", "</script", "javascript:", "<iframe", "<object", "<embed", "<link", "<meta"] {
            salida = salida.replacingOccurrences(of: patron, with: "", options: .caseInsensitive)
        }
        return salida.replacingOccurrences(of: #"on\w+="#, with: "", options: [.regularExpression, .caseInsensitive])
    }

    static func soloDigitos(_ texto: String) -> String {
        texto.filter(\.isNumber)
    }

    static func esTelefono(_ texto: String) -> Bool {
        texto.count == 10 && texto.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
