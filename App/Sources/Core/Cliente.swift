import Foundation

enum Categoria: String, CaseIterable, Identifiable {
    case activos
    case sinrenovar
    case prospectos
    case prAprobadas = "pr-aprobadas"
    case prRechazadas = "pr-rechazadas"
    case fraude

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .activos: return "Clientes activos"
        case .sinrenovar: return "Sin renovar"
        case .prospectos: return "Prospectos"
        case .prAprobadas: return "PR aprobadas"
        case .prRechazadas: return "PR rechazadas"
        case .fraude: return "Fraude"
        }
    }

    var icono: String {
        switch self {
        case .activos: return "person.2.fill"
        case .sinrenovar: return "arrow.triangle.2.circlepath"
        case .prospectos: return "scope"
        case .prAprobadas: return "checkmark.seal.fill"
        case .prRechazadas: return "xmark.seal.fill"
        case .fraude: return "exclamationmark.triangle.fill"
        }
    }

    var esPR: Bool { self == .prAprobadas || self == .prRechazadas }
}

enum Estatus: String, CaseIterable, Identifiable {
    case alCorriente = "al-corriente"
    case atraso
    case fraude

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .alCorriente: return "Al corriente"
        case .atraso: return "En atraso"
        case .fraude: return "Fraude"
        }
    }
}

struct Referencia: Equatable {
    var nombre: String
    var tel: String

    var json: JSON { .object(["nombre": .string(nombre), "tel": .string(tel)]) }
}

struct Seguimiento: Equatable {
    var tipo: String
    var notas: String
    var fecha: String?

    static let tipos = ["Llamada", "Visita", "Mensaje"]
}

/// A record in `ca_clientes`. Every category (active client, prospect, PR, fraud…) shares this
/// shape; `raw` keeps the complete record and the properties below are typed views onto it.
struct Cliente: Identifiable, Equatable {
    var raw: [String: JSON]

    init(raw: [String: JSON]) { self.raw = raw }

    subscript(campo: String) -> JSON? {
        get { raw[campo] }
        set { raw[campo] = (newValue?.isNull ?? true) ? nil : newValue }
    }

    private func texto(_ campo: String) -> String? {
        guard let valor = raw[campo]?.text, !valor.isEmpty else { return nil }
        return valor
    }

    private mutating func poner(_ campo: String, _ valor: String?) {
        raw[campo] = valor.map(JSON.string)
    }

    var id: String {
        get { raw["id"]?.text ?? "" }
        set { raw["id"] = .string(newValue) }
    }

    var nombre: String {
        get { raw["nombre"]?.text ?? "" }
        set { raw["nombre"] = .string(newValue) }
    }

    var tel: String {
        get { raw["tel"]?.text ?? "" }
        set { raw["tel"] = .string(newValue) }
    }

    var categoriaTexto: String {
        get { raw["categoria"]?.text ?? "" }
        set { raw["categoria"] = .string(newValue) }
    }

    var categoria: Categoria? {
        get { Categoria(rawValue: categoriaTexto) }
        set { categoriaTexto = newValue?.rawValue ?? "" }
    }

    var estatusTexto: String {
        get { texto("estatus") ?? Estatus.alCorriente.rawValue }
        set { raw["estatus"] = .string(newValue) }
    }

    var estatus: Estatus { Estatus(rawValue: estatusTexto) ?? .alCorriente }

    var tieneWA: Bool {
        get { raw["tieneWA"]?.truthy ?? false }
        set { raw["tieneWA"] = .bool(newValue) }
    }

    var sl: String? { get { texto("sl") } set { poner("sl", newValue) } }
    var curp: String? { get { texto("curp") } set { poner("curp", newValue) } }
    var asesor: String? { get { texto("asesor") } set { poner("asesor", newValue) } }
    var tipo: String? { get { texto("tipo") } set { poner("tipo", newValue) } }
    var fechaCompra: String? { get { texto("fechaCompra") } set { poner("fechaCompra", newValue) } }
    var semanas: String? { get { texto("semanas") } set { poner("semanas", newValue) } }
    var numPR: String? { get { texto("numPR") } set { poner("numPR", newValue) } }
    var tipocred: String? { get { texto("tipocred") } set { poner("tipocred", newValue) } }
    var fechaSolicitud: String? { get { texto("fechaSolicitud") } set { poner("fechaSolicitud", newValue) } }
    var fechaIngresoPR: String? { get { texto("fechaIngresoPR") } set { poner("fechaIngresoPR", newValue) } }
    var detallesPR: String? { get { texto("detallesPR") } set { poner("detallesPR", newValue) } }
    var fechaRef: String? { get { texto("fechaRef") } set { poner("fechaRef", newValue) } }
    var origen: String? { get { texto("origen") } set { poner("origen", newValue) } }
    var refDeId: String? { get { texto("refDeId") } set { poner("refDeId", newValue) } }
    var dobleFinId: String? { get { texto("dobleFinId") } set { poner("dobleFinId", newValue) } }
    var notas: String? { get { texto("notas") } set { poner("notas", newValue) } }

    var inhabilitado: Bool { raw["inhabilitado"]?.truthy ?? false }
    var verificado: Bool { raw["verificado"]?.truthy ?? false }
    var suspendido: Bool { raw["suspendido"]?.truthy ?? false }
    var esPRAprobada: Bool { raw["esPRAprobada"]?.truthy ?? false }

    var pagosConfirmados: [Int] {
        get { raw["pagosConfirmados"]?.list?.compactMap(\.int) ?? [] }
        set { raw["pagosConfirmados"] = .from(newValue) }
    }

    var pagosMarcadosNoPagado: [Int] {
        get { raw["pagosMarcadosNoPagado"]?.list?.compactMap(\.int) ?? [] }
        set { raw["pagosMarcadosNoPagado"] = .from(newValue) }
    }

    /// Milliseconds of the last "no pagado" mark.
    var ultimoMarcadoNoPagado: Double { raw["ultimoMarcadoNoPagado"]?.number ?? 0 }

    var refs: [Referencia] {
        get {
            (raw["refs"]?.list ?? []).map {
                Referencia(nombre: $0["nombre"]?.text ?? "", tel: $0["tel"]?.text ?? "")
            }
        }
        set { raw["refs"] = .array(newValue.map(\.json)) }
    }

    var seguimiento: Seguimiento? {
        get {
            guard let valor = raw["seguimiento"], valor.object != nil else { return nil }
            return Seguimiento(tipo: valor["tipo"]?.text ?? "", notas: valor["notas"]?.text ?? "", fecha: valor["fecha"]?.text)
        }
        set {
            guard let nuevo = newValue else { raw["seguimiento"] = nil; return }
            raw["seguimiento"] = .object([
                "tipo": .string(nuevo.tipo),
                "notas": .string(nuevo.notas),
                "fecha": .from(nuevo.fecha),
            ])
        }
    }

    /// Empty string and absent both mean "no value", matching the web app.
    var macropesos: Double? {
        guard let valor = raw["macropesos"], let numero = valor.number, numero.isFinite else { return nil }
        if case .string(let texto) = valor, texto.isEmpty { return nil }
        return numero
    }

    var historial: [JSON] { raw["historial"]?.list ?? [] }

    /// The PR attached to a "sin renovar" client.
    var prActual: [String: JSON]? { raw["prActual"]?.object }

    var tieneTelefonoWA: Bool { tieneWA && !tel.isEmpty }
}

extension Cliente {
    /// Fills the defaults the web app applies after every load.
    func normalizado() -> Cliente {
        var copia = self
        if copia.raw["pagosConfirmados"] == nil { copia.raw["pagosConfirmados"] = .array([]) }
        if copia.texto("estatus") == nil { copia.raw["estatus"] = .string(Estatus.alCorriente.rawValue) }
        if copia.raw["tieneWA"] == nil { copia.raw["tieneWA"] = .bool(true) }
        if copia.fechaIngresoPR == nil, copia.categoria?.esPR == true { copia.fechaIngresoPR = Fecha.hoyISO }
        return copia
    }
}

/// "María  José Pérez" and "maria jose perez" are the same person.
func normalizarNombre(_ texto: String?) -> String {
    guard let texto else { return "" }
    let sinAcentos = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_MX"))
    return sinAcentos.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
}
