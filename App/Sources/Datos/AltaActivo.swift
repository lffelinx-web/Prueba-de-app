import Foundation

struct DatosActivo {
    var id: String?
    var nombre = ""
    var tel = ""
    var tieneWA = true
    var compra = ""
    var sl = "SL"
    var curp = ""
    var semanas = ""
    var asesor = ""
    var tipo = ""
    var refs: [Referencia] = []

    // Filled while resolving matches with existing records.
    var esDoble = false
    var vinculadoConId: String?
    var historialRenovacion: [JSON] = []
    var renovacionEliminarIds: [String] = []
    var refsARelink: [String] = []
}

struct ProspectoDuplicado: Identifiable {
    let prospecto: Cliente
    let etiqueta: String       // "Ref. 1" / "Ref. 2"
    let nombreReferencia: String
    var id: String { prospecto.id }
}

enum Discrepancia { case nombre, tel, ambos }

enum EleccionDatos { case nuevo, existente }

/// The questions the web app asks while saving an active client.
enum PasoAlta: Identifiable {
    case prospectosDuplicados([ProspectoDuplicado])
    case dobleFinanciamiento(existente: Cliente, motivos: [String], telefonoDistinto: Bool)
    case coincidencia(encontrado: Cliente, discrepancia: Discrepancia?)

    var id: String {
        switch self {
        case .prospectosDuplicados: return "prospectos"
        case .dobleFinanciamiento(let existente, _, _): return "doble-" + existente.id
        case .coincidencia(let encontrado, _): return "coincidencia-" + encontrado.id
        }
    }
}

/// Saving an active client, step by step, ported from `guardarActivo` and the functions it chains:
/// references already registered as prospects, double financing with another active credit,
/// and the same person found in "sin renovar", prospects or PRs. Every intermediate change is
/// kept in `trabajo` and written once, when the flow finishes.
@MainActor
final class AltaActivo: ObservableObject {
    @Published var paso: PasoAlta?
    @Published var error = ""
    @Published private(set) var terminado = false

    private var store: Store!
    private var trabajo: [Cliente] = []
    private var pendiente = DatosActivo()

    /// The values being saved, to show next to the matching record.
    var datosPendientes: DatosActivo { pendiente }

    func usar(_ store: Store) { self.store = store }

    private static let categoriasBusqueda: Set<Categoria> = [.sinrenovar, .prospectos, .prAprobadas, .prRechazadas]

    func iniciar(_ entrada: DatosActivo) async {
        error = ""
        trabajo = store.clientes
        var d = entrada
        d.nombre = Texto.limpio(d.nombre)
        d.tel = d.tel.trimmingCharacters(in: .whitespaces)
        let sl = d.sl.trimmingCharacters(in: .whitespaces).uppercased()
        d.sl = sl.hasPrefix("SL") ? sl : "SL" + sl
        d.curp = Texto.limpio(d.curp).uppercased()
        d.refs = d.refs.map { Referencia(nombre: Texto.limpio($0.nombre), tel: $0.tel.trimmingCharacters(in: .whitespaces)) }
        let ref1 = d.refs.first?.tel ?? "", ref2 = d.refs.count > 1 ? d.refs[1].tel : ""

        if d.nombre.isEmpty { return fallar("El nombre es requerido.") }
        if !Texto.esTelefono(d.tel) { return fallar("Teléfono: 10 dígitos exactos.") }
        if d.compra.isEmpty { return fallar("La fecha de compra es requerida.") }
        if d.sl.range(of: #"^SL\d{12}$"#, options: .regularExpression) == nil { return fallar("SL debe ser: SL + 12 dígitos.") }
        if d.semanas.isEmpty { return fallar("Selecciona el plazo.") }
        if d.asesor.isEmpty { return fallar("Selecciona el asesor.") }
        if d.tipo.isEmpty { return fallar("Selecciona el tipo de crédito.") }
        if !ref1.isEmpty, !Texto.esTelefono(ref1) { return fallar("Ref. 1: teléfono de 10 dígitos.") }
        if !ref2.isEmpty, !Texto.esTelefono(ref2) { return fallar("Ref. 2: teléfono de 10 dígitos.") }
        if ref1 == d.tel { return fallar("Ref. 1: el teléfono es igual al del cliente.") }
        if ref2 == d.tel { return fallar("Ref. 2: el teléfono es igual al del cliente.") }
        if !ref1.isEmpty, ref1 == ref2 { return fallar("Ref. 1 y Ref. 2 tienen el mismo teléfono.") }
        if d.id == nil, !store.visibilidadCargada || !store.asesorDisponible(d.asesor) {
            return fallar("Selecciona un asesor disponible para nuevas altas.")
        }

        // A reference's phone may not belong to another client; prospects can be absorbed instead.
        func duenoDelTelefono(_ tel: String) -> Cliente? {
            guard !tel.isEmpty else { return nil }
            return trabajo.first { c in
                if c.id == d.id || c.inhabilitado { return false }
                if let id = d.id, c.categoria == .prospectos, c.refDeId == id { return false }
                return c.tel == tel
            }
        }
        var duplicados: [ProspectoDuplicado] = []
        for (n, tel) in [ref1, ref2].enumerated() {
            guard let dueno = duenoDelTelefono(tel) else { continue }
            guard dueno.categoria == .prospectos else {
                return fallar("Ref. \(n + 1): el teléfono \(tel) ya existe en \(dueno.categoria?.titulo ?? dueno.categoriaTexto) (\(dueno.nombre)).")
            }
            duplicados.append(ProspectoDuplicado(prospecto: dueno, etiqueta: "Ref. \(n + 1)", nombreReferencia: d.refs[n].nombre))
        }
        // Only references with a name are kept.
        d.refs = d.refs.filter { !$0.nombre.isEmpty }
        pendiente = d

        if !duplicados.isEmpty {
            paso = .prospectosDuplicados(duplicados)
            return
        }
        await revisarCoincidencias()
    }

    /// The prospects matching the references are disabled and the save continues.
    func absorberProspectos(_ duplicados: [ProspectoDuplicado]) async {
        paso = nil
        for item in duplicados {
            guard let i = trabajo.firstIndex(where: { $0.id == item.prospecto.id }) else { continue }
            trabajo[i]["inhabilitado"] = true
            trabajo[i]["inhabilitadoMotivo"] = .string("Convertido en referencia de \(pendiente.nombre)")
            trabajo[i]["inhabilitadoFecha"] = .string(Fecha.hoyISO)
        }
        await revisarCoincidencias()
    }

    /// New clients only: another active credit first, then the rest of the database.
    private func revisarCoincidencias() async {
        let d = pendiente
        guard d.id == nil else { return await ejecutar(d) }
        if let activo = activoCoincidente(d) {
            return pedirDobleFinanciamiento(activo, d)
        }
        let nombre = normalizarNombre(d.nombre)
        if let encontrado = trabajo.first(where: { c in
            guard let categoria = c.categoria, AltaActivo.categoriasBusqueda.contains(categoria), !c.inhabilitado else { return false }
            return (!nombre.isEmpty && nombre == normalizarNombre(c.nombre)) || (!d.curp.isEmpty && d.curp == c.curp)
        }) {
            return pedirCoincidencia(encontrado, d)
        }
        await ejecutar(d)
    }

    private func activoCoincidente(_ d: DatosActivo) -> Cliente? {
        let nombre = normalizarNombre(d.nombre)
        return trabajo.first { c in
            guard c.categoria == .activos else { return false }
            return (!nombre.isEmpty && nombre == normalizarNombre(c.nombre))
                || (!d.curp.isEmpty && d.curp == c.curp)
                || (!d.tel.isEmpty && d.tel == c.tel)
        }
    }

    private func pedirDobleFinanciamiento(_ existente: Cliente, _ d: DatosActivo) {
        var motivos: [String] = []
        if normalizarNombre(d.nombre) == normalizarNombre(existente.nombre) { motivos.append("nombre completo") }
        if let curp = existente.curp, curp == d.curp { motivos.append("CURP") }
        if !existente.tel.isEmpty, existente.tel == d.tel { motivos.append("teléfono") }
        pendiente = d
        pendiente.vinculadoConId = existente.id
        paso = .dobleFinanciamiento(existente: existente, motivos: motivos, telefonoDistinto: !existente.tel.isEmpty && existente.tel != d.tel)
    }

    private func pedirCoincidencia(_ encontrado: Cliente, _ d: DatosActivo) {
        let mismoNombre = d.nombre.trimmingCharacters(in: .whitespaces).lowercased() == encontrado.nombre.trimmingCharacters(in: .whitespaces).lowercased()
        let mismoTel = d.tel == encontrado.tel
        let discrepancia: Discrepancia? = mismoNombre && mismoTel ? nil : (!mismoNombre && !mismoTel ? .ambos : (mismoNombre ? .tel : .nombre))
        pendiente = d
        paso = .coincidencia(encontrado: encontrado, discrepancia: discrepancia)
    }

    /// `telefono`: which phone is current when the two credits differ (nil when they match).
    func confirmarDobleFinanciamiento(telefono: EleccionDatos?) async {
        paso = nil
        var d = pendiente
        guard let existenteId = d.vinculadoConId, let j = trabajo.firstIndex(where: { $0.id == existenteId }) else { return }
        switch telefono {
        case .existente?: d.tel = trabajo[j].tel
        case .nuevo?: trabajo[j].tel = d.tel
        case nil: break
        }
        d.esDoble = true
        await ejecutar(d)
    }

    func confirmarCoincidencia(_ encontrado: Cliente, discrepancia: Discrepancia?, eleccion: EleccionDatos?) async {
        paso = nil
        var d = pendiente
        guard let idx = trabajo.firstIndex(where: { $0.id == encontrado.id }) else { return }
        let actual = trabajo[idx]
        if let discrepancia, let eleccion {
            let cambiaNombre = discrepancia == .nombre || discrepancia == .ambos
            let cambiaTel = discrepancia == .tel || discrepancia == .ambos
            if eleccion == .existente {
                if cambiaNombre { d.nombre = actual.nombre }
                if cambiaTel { d.tel = actual.tel }
            } else if actual.categoria != .sinrenovar {
                if cambiaNombre { trabajo[idx].nombre = d.nombre }
                if cambiaTel { trabajo[idx].tel = d.tel }
            }
        }

        switch actual.categoria {
        case .sinrenovar?:
            // Renewal: the old credit becomes history of the new one.
            var entrada = Reglas.entradaHistorial(de: actual, fechaFin: actual.fechaFin.map(Fecha.iso)).object ?? [:]
            entrada["estatus"] = .string(actual.estatusTexto)
            entrada["macropesos"] = actual["macropesos"] ?? .string("")
            entrada["nombre"] = .string(actual.nombre)
            entrada["tel"] = .string(actual.tel)
            entrada["curp"] = .string(actual.curp ?? "")
            var eliminar = d.renovacionEliminarIds + [actual.id]
            if let pr = actual.prActual {
                if let prId = pr["clientePRId"]?.text { eliminar.append(prId) }
                var historialPR = actual["historialPR"]?.list ?? []
                var archivada = pr
                archivada["fechaEliminacion"] = .string(Fecha.hoyISO)
                archivada["motivo"] = "cliente reactivado como activo"
                historialPR.append(.object(archivada))
                entrada["historialPR"] = .array(historialPR)
            } else if let historialPR = actual["historialPR"] {
                entrada["historialPR"] = historialPR
            }
            d.historialRenovacion += actual.historial + [.object(entrada)]
            d.renovacionEliminarIds = eliminar
            d.refsARelink += trabajo.filter { $0.refDeId == actual.id && $0.categoria == .prospectos }.map(\.id)
        case .prospectos?:
            trabajo[idx]["inhabilitado"] = true
        case .prAprobadas?, .prRechazadas?:
            trabajo.remove(at: idx)
        default:
            break
        }
        await chequeoFinal(d)
    }

    /// `_guardarActivoConChequeoDoble`: another renewal, then double financing, then save.
    private func chequeoFinal(_ d: DatosActivo) async {
        let nombre = normalizarNombre(d.nombre)
        let retirados = Set(d.renovacionEliminarIds)
        if let anterior = trabajo.first(where: { c in
            !retirados.contains(c.id) && !c.inhabilitado && c.categoria == .sinrenovar
                && ((!nombre.isEmpty && nombre == normalizarNombre(c.nombre)) || (!d.curp.isEmpty && d.curp == c.curp))
        }) {
            return pedirCoincidencia(anterior, d)
        }
        if let activo = activoCoincidente(d) {
            return pedirDobleFinanciamiento(activo, d)
        }
        await ejecutar(d)
    }

    func cancelar() {
        paso = nil
        trabajo = []
    }

    private func fallar(_ mensaje: String) {
        error = mensaje
    }

    /// `_ejecutarGuardarActivo`.
    private func ejecutar(_ d: DatosActivo) async {
        var lista = trabajo
        let existente = d.id.flatMap { id in lista.first { $0.id == id } }
        var obj = existente ?? Cliente(raw: [
            "id": .string(Identificador.nuevo()),
            "categoria": .string(Categoria.activos.rawValue),
            "pagosConfirmados": .array([]),
            "macropesos": .string(""),
            "estatus": .string(Estatus.alCorriente.rawValue),
        ])
        obj.nombre = d.nombre
        obj.tel = d.tel
        obj.tieneWA = d.tieneWA
        obj["fechaCompra"] = .string(d.compra)
        obj["sl"] = .string(d.sl)
        obj["curp"] = .string(d.curp)
        obj["semanas"] = .string(d.semanas)
        obj["asesor"] = .string(d.asesor)
        obj["tipo"] = .string(d.tipo)
        obj.refs = d.refs
        if !d.historialRenovacion.isEmpty {
            obj["historial"] = .array(obj.historial + d.historialRenovacion)
        }

        if !d.renovacionEliminarIds.isEmpty {
            let retirar = Set(d.renovacionEliminarIds)
            lista.removeAll { retirar.contains($0.id) }
            for i in lista.indices where retirar.contains(lista[i].dobleFinId ?? "") { lista[i].dobleFinId = nil }
        }

        if d.esDoble, let otroId = d.vinculadoConId {
            obj.dobleFinId = otroId
            if let j = lista.firstIndex(where: { $0.id == otroId }), existente == nil || lista[j].dobleFinId == nil {
                lista[j].dobleFinId = obj.id
            }
        }

        var pedirPagos = false
        if let existente, let i = lista.firstIndex(where: { $0.id == existente.id }) {
            lista[i] = obj
            AltaActivo.sincronizarReferencias(de: obj.id, refs: d.refs, titular: obj.nombre, asesor: d.asesor, en: &lista)
        } else {
            for i in lista.indices where d.refsARelink.contains(lista[i].id) {
                lista[i].refDeId = obj.id
                lista[i].origen = "Ref. de \(d.nombre)"
            }
            // An already finished credit goes straight to "sin renovar".
            if let fin = obj.fechaFin, fin <= Fecha.hoy {
                obj.pagosConfirmados = [1, 2, 3, 4]
                obj.categoria = .sinrenovar
            } else {
                pedirPagos = true
            }
            lista.append(obj)
            for ref in d.refs {
                let yaExiste = lista.contains { c in
                    c.categoria == .prospectos && c.refDeId == obj.id
                        && normalizarNombre(c.nombre) == normalizarNombre(ref.nombre) && c.tel == ref.tel
                }
                if !yaExiste {
                    lista.append(AltaActivo.prospectoDeReferencia(ref, titular: d.nombre, titularId: obj.id, asesor: d.asesor, fecha: d.compra))
                }
            }
        }

        guard await store.guardar(lista) else { return }
        terminado = true
        if pedirPagos {
            var guardado = obj
            guardado.categoria = .activos
            if !guardado.pagosPasadosSinConfirmar.isEmpty {
                // After the form's sheet has gone, so the new sheet can be presented.
                let id = obj.id, store = store
                Task {
                    try? await Task.sleep(for: .milliseconds(800))
                    store?.revisarPagosDe = id
                }
            }
        }
    }

    static func prospectoDeReferencia(_ ref: Referencia, titular: String, titularId: String, asesor: String, fecha: String?) -> Cliente {
        var raw: [String: JSON] = [
            "id": .string(Identificador.referencia()),
            "nombre": .string(ref.nombre),
            "tel": .string(ref.tel),
            "tieneWA": true,
            "asesor": .string(asesor),
            "categoria": .string(Categoria.prospectos.rawValue),
            "origen": .string("Ref. de \(titular)"),
            "refDeId": .string(titularId),
            "pagosConfirmados": .array([]),
            "estatus": .string(Estatus.alCorriente.rawValue),
        ]
        if let fecha { raw["fechaRef"] = .string(fecha) }
        return Cliente(raw: raw)
    }

    /// Keeps the prospects created from a client's references in step with its edited references.
    static func sincronizarReferencias(de clienteId: String, refs: [Referencia], titular: String, asesor: String, en lista: inout [Cliente]) {
        let vinculados = lista.filter { $0.refDeId == clienteId && $0.categoria == .prospectos }.map(\.id)
        for (n, ref) in refs.enumerated() where !ref.nombre.isEmpty {
            if n < vinculados.count, let i = lista.firstIndex(where: { $0.id == vinculados[n] }) {
                lista[i].nombre = ref.nombre
                lista[i].tel = ref.tel
                lista[i].origen = "Ref. de \(titular)"
            } else {
                lista.append(prospectoDeReferencia(ref, titular: titular, titularId: clienteId, asesor: asesor, fecha: nil))
            }
        }
        if vinculados.count > refs.count {
            let sobrantes = Set(vinculados[refs.count...])
            lista.removeAll { sobrantes.contains($0.id) }
        }
    }
}
