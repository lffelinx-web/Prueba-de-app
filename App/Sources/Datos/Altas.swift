import Foundation

struct DatosProspecto {
    var id: String?
    var nombre = ""
    var tel = ""
    var tieneWA = true
    var fecha = Fecha.hoyISO
    var asesor = ""
    var inhabilitado = false
    var verificado = false
    var refDeId: String?
}

struct DatosPR {
    var id: String?
    var categoria: Categoria = .prAprobadas
    var nombre = ""
    var tel = ""
    var tieneWA = true
    var numPR = "PR"
    var asesor = ""
    var fechaSolicitud = Fecha.hoyISO
    var tipocred = ""
    var detalles = ""
}

struct DatosFraude {
    var id: String?
    var nombre = ""
    var tel = ""
    var curp = ""
    var notas = ""
}

/// A "sin renovar" client that may be the same person as a new PR.
struct CandidatoPR: Identifiable {
    let cliente: Cliente
    let coincideNombre: Bool
    let coincideTel: Bool
    var id: String { cliente.id }
}

enum ResultadoAlta {
    case error(String)
    case guardado
    case candidatosPR([CandidatoPR], DatosPR)
}

extension Store {
    private func asesorValidoParaAlta(_ asesor: String) -> Bool {
        visibilidadCargada && (asesor.isEmpty || asesorDisponible(asesor))
    }

    // MARK: - Prospects

    func guardarProspecto(_ entrada: DatosProspecto) async -> ResultadoAlta {
        var d = entrada
        d.nombre = Texto.limpio(d.nombre)
        d.tel = d.tel.trimmingCharacters(in: .whitespaces)
        if d.nombre.isEmpty { return .error("El nombre es requerido.") }
        if !d.inhabilitado, !Texto.esTelefono(d.tel) { return .error("Teléfono: 10 dígitos exactos.") }
        if d.fecha.isEmpty { return .error("La fecha es requerida.") }
        if d.id == nil, !asesorValidoParaAlta(d.asesor) { return .error("Selecciona un asesor disponible para nuevas altas.") }

        var lista = clientes
        let existente = d.id.flatMap { id in lista.first { $0.id == id } }
        let refDeId = d.refDeId ?? existente?.refDeId
        let padre = refDeId.flatMap { id in lista.first { $0.id == id } }

        var obj = existente ?? Cliente(raw: ["id": .string(Identificador.nuevo())])
        obj.nombre = d.nombre
        obj.tel = d.tel
        obj.tieneWA = d.tieneWA
        obj["asesor"] = .string(d.asesor)
        obj["inhabilitado"] = .bool(d.inhabilitado)
        obj["verificado"] = .bool(d.verificado)
        obj.refDeId = padre == nil ? existente?.refDeId : refDeId
        obj.categoria = .prospectos
        obj.origen = padre.map { "Ref. de \($0.nombre)" } ?? existente?.origen ?? "Manual"
        obj.fechaRef = d.fecha
        obj.pagosConfirmados = []
        obj.estatusTexto = existente?.estatusTexto ?? Estatus.alCorriente.rawValue

        if let i = lista.firstIndex(where: { $0.id == obj.id }) {
            lista[i] = obj
        } else {
            lista.append(obj)
        }

        // A prospect that is someone's reference keeps that client's reference list in step.
        if let padreId = obj.refDeId, let p = lista.firstIndex(where: { $0.id == padreId }) {
            var refs = lista[p].refs
            let vinculados = lista.filter { $0.refDeId == padreId && $0.categoria == .prospectos }
            if let posicion = vinculados.firstIndex(where: { $0.id == obj.id }), posicion < refs.count {
                refs[posicion] = Referencia(nombre: obj.nombre, tel: obj.tel)
                lista[p].refs = refs
            }
        }
        return await guardar(lista) ? .guardado : .error("")
    }

    /// Active and "sin renovar" clients a prospect can be linked to as a reference.
    func titularesPosibles(_ busqueda: String) -> [Cliente] {
        let q = busqueda.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(clientes.filter { c in
            (c.categoria == .activos || c.categoria == .sinrenovar) && (c.nombre.lowercased().contains(q) || c.tel.contains(q))
        }.prefix(8))
    }

    // MARK: - PRs

    func guardarPR(_ entrada: DatosPR) async -> ResultadoAlta {
        var d = entrada
        d.nombre = Texto.limpio(d.nombre)
        d.tel = d.tel.trimmingCharacters(in: .whitespaces)
        let num = d.numPR.trimmingCharacters(in: .whitespaces).uppercased()
        d.numPR = num.hasPrefix("PR") ? num : "PR" + num
        d.detalles = Texto.limpio(d.detalles)
        if d.nombre.isEmpty { return .error("El nombre es requerido.") }
        if !Texto.esTelefono(d.tel) { return .error("Teléfono: 10 dígitos.") }
        if d.numPR.range(of: #"^PR\d{12}$"#, options: .regularExpression) == nil { return .error("PR: PR + 12 dígitos.") }
        if d.asesor.isEmpty { return .error("Selecciona el asesor.") }
        if d.fechaSolicitud.isEmpty { return .error("La fecha de solicitud es requerida.") }
        if d.tipocred.isEmpty { return .error("Selecciona el tipo (Financing o Créditos).") }
        if d.id == nil, !asesorValidoParaAlta(d.asesor) { return .error("Selecciona un asesor disponible para nuevas altas.") }

        if d.id == nil {
            let nombre = normalizarNombre(d.nombre)
            let candidatos = clientes
                .filter { $0.categoria == .sinrenovar && $0.prActual == nil }
                .map { CandidatoPR(cliente: $0, coincideNombre: normalizarNombre($0.nombre) == nombre, coincideTel: $0.tel == d.tel) }
                .filter { $0.coincideNombre || $0.coincideTel }
            if !candidatos.isEmpty { return .candidatosPR(candidatos, d) }
        }
        return await guardarPRNormal(d)
    }

    func guardarPRNormal(_ d: DatosPR) async -> ResultadoAlta {
        var lista = clientes
        let existente = d.id.flatMap { id in lista.first { $0.id == id } }
        var obj = existente ?? Cliente(raw: ["id": .string(Identificador.nuevo())])
        aplicar(d, a: &obj)
        obj.fechaIngresoPR = existente?.fechaIngresoPR ?? Fecha.hoyISO
        if let i = lista.firstIndex(where: { $0.id == obj.id }) {
            lista[i] = obj
        } else {
            lista.append(obj)
        }
        return await guardar(lista) ? .guardado : .error("")
    }

    private func aplicar(_ d: DatosPR, a obj: inout Cliente) {
        obj.nombre = d.nombre
        obj.tel = d.tel
        obj.tieneWA = d.tieneWA
        obj["numPR"] = .string(d.numPR)
        obj["asesor"] = .string(d.asesor)
        obj["fechaSolicitud"] = .string(d.fechaSolicitud)
        obj["tipocred"] = .string(d.tipocred)
        obj["detallesPR"] = .string(d.detalles)
        obj.categoria = d.categoria
        obj.pagosConfirmados = []
        obj.estatusTexto = Estatus.alCorriente.rawValue
    }

    /// Attaches the new PR to a "sin renovar" client and creates the PR record linked to it.
    func adjuntarPR(_ d: DatosPR, a clienteId: String) async -> Bool {
        var lista = clientes
        guard let i = lista.firstIndex(where: { $0.id == clienteId }) else { return false }
        var nuevo = Cliente(raw: ["id": .string(Identificador.nuevo())])
        aplicar(d, a: &nuevo)
        nuevo.fechaIngresoPR = Fecha.hoyISO
        nuevo["clienteSinRenovarId"] = .string(clienteId)
        lista[i]["prActual"] = .object([
            "numPR": .string(d.numPR),
            "asesor": .string(d.asesor),
            "fechaSolicitud": .string(d.fechaSolicitud),
            "tipocred": .string(d.tipocred),
            "detallesPR": .string(d.detalles),
            "estatus": .string(d.categoria == .prAprobadas ? "aprobada" : "rechazada"),
            "fechaIngresoPR": .string(Fecha.hoyISO),
            "clienteSinRenovarId": .string(clienteId),
            "clientePRId": .string(nuevo.id),
        ])
        lista.append(nuevo)
        return await guardar(lista)
    }

    // MARK: - Fraud

    func guardarFraude(_ entrada: DatosFraude) async -> ResultadoAlta {
        let nombre = Texto.limpio(entrada.nombre)
        if nombre.isEmpty { return .error("El nombre es requerido.") }
        var lista = clientes
        var obj = entrada.id.flatMap { id in lista.first { $0.id == id } }
            ?? Cliente(raw: ["id": .string(Identificador.nuevo()), "pagosConfirmados": .array([]), "tieneWA": false])
        obj.nombre = nombre
        obj.tel = entrada.tel.trimmingCharacters(in: .whitespaces)
        obj["curp"] = .string(Texto.limpio(entrada.curp).uppercased())
        obj["notas"] = .string(Texto.limpio(entrada.notas))
        obj.categoria = .fraude
        obj.estatusTexto = Estatus.fraude.rawValue
        if let i = lista.firstIndex(where: { $0.id == obj.id }) {
            lista[i] = obj
        } else {
            lista.append(obj)
        }
        return await guardar(lista) ? .guardado : .error("")
    }
}
