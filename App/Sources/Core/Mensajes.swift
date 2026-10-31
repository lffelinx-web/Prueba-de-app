import Foundation

// MARK: - Templates

/// Reminder templates, stored per user under `ca_recordatorios_plantillas/<usuario>/<tipo>`.
enum TipoRecordatorio: String, CaseIterable, Identifiable {
    case pagosHoy = "primerospagos"
    case pagosAtrasados = "pagosatrasados"
    case macropesosDisponibles = "macropesos-disp"
    case macropesosInvitacion = "macropesos-inv"
    case creditoDisponible = "credito-disp"

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .pagosHoy: return "Pagos de hoy"
        case .pagosAtrasados: return "Pagos atrasados"
        case .macropesosDisponibles: return "Macropesos disponibles"
        case .macropesosInvitacion: return "Invitación para macropesos"
        case .creditoDisponible: return "Crédito disponible"
        }
    }

    var descripcion: String {
        switch self {
        case .pagosHoy: return "Recordatorio cuando el pago vence hoy"
        case .pagosAtrasados: return "Recordatorio para pagos vencidos sin confirmar"
        case .macropesosDisponibles: return "Aviso de macropesos disponibles del cliente"
        case .macropesosInvitacion: return "Invitación para ganar más macropesos"
        case .creditoDisponible: return "Clientes con crédito disponible para renovar"
        }
    }

    var icono: String {
        switch self {
        case .pagosHoy: return "dollarsign.circle"
        case .pagosAtrasados: return "exclamationmark.triangle"
        case .macropesosDisponibles: return "banknote"
        case .macropesosInvitacion: return "gift"
        case .creditoDisponible: return "chart.bar"
        }
    }

    var marcadores: [String] {
        switch self {
        case .pagosHoy, .pagosAtrasados: return ["[numero de pago]"]
        case .macropesosDisponibles, .macropesosInvitacion: return ["[macropesos]"]
        case .creditoDisponible: return ["[linea de crédito]"]
        }
    }
}

struct PlantillaRecordatorio: Equatable {
    var saludo = ""
    var lugar = ""
    var cuerpo = ""
    /// Only "macropesos disponibles": a second body that offers an accessory from the catalogue.
    var avanzadasActivas = false
    var cuerpoAvanzado = ""

    init() {}

    init(_ json: JSON?) {
        saludo = json?["saludo"]?.text ?? ""
        lugar = json?["lugar"]?.text ?? ""
        cuerpo = json?["cuerpo"]?.text ?? ""
        avanzadasActivas = json?["avanzadasActivas"]?.truthy ?? false
        cuerpoAvanzado = json?["cuerpoAvanzado"]?.text ?? ""
    }

    var tieneContenido: Bool { !saludo.isEmpty || !lugar.isEmpty || !cuerpo.isEmpty }

    func json(tipo: TipoRecordatorio) -> JSON {
        var valor: [String: JSON] = ["saludo": .string(saludo), "lugar": .string(lugar), "cuerpo": .string(cuerpo)]
        if tipo == .macropesosDisponibles {
            valor["avanzadasActivas"] = .bool(avanzadasActivas)
            valor["cuerpoAvanzado"] = .string(cuerpoAvanzado)
        }
        return .object(valor)
    }
}

/// Message templates, stored per user under `ca_mensajes_pred/<usuario>/<categoría>`.
enum CategoriaMensaje: String, CaseIterable, Identifiable {
    case sinrenovar
    case porfinalizar
    case prAprobadas = "pr-aprobadas"
    case prospectos
    case prospectosVerificados = "prospectos-verificados"

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .sinrenovar: return "Clientes sin renovar"
        case .porfinalizar: return "Clientes por finalizar"
        case .prAprobadas: return "PR aprobadas"
        case .prospectos: return "Prospectos"
        case .prospectosVerificados: return "Prospectos verificados"
        }
    }

    var descripcion: String {
        switch self {
        case .sinrenovar: return "Créditos no renovados"
        case .porfinalizar: return "Restan 5 semanas o menos"
        case .prAprobadas: return "Clientes con PR aprobada"
        case .prospectos: return "Posibles clientes"
        case .prospectosVerificados: return "Solo prospectos marcados como verificados"
        }
    }

    var icono: String {
        switch self {
        case .sinrenovar: return "arrow.triangle.2.circlepath"
        case .porfinalizar: return "hourglass"
        case .prAprobadas: return "checkmark.seal.fill"
        case .prospectos: return "scope"
        case .prospectosVerificados: return "checkmark.circle"
        }
    }

    /// Categories with a configurable template.
    static let conPlantilla: [CategoriaMensaje] = [.sinrenovar, .porfinalizar, .prAprobadas, .prospectosVerificados]
    static let masivos: [CategoriaMensaje] = [.prAprobadas, .prospectos, .sinrenovar, .porfinalizar]
    static let personalizados: [CategoriaMensaje] = [.sinrenovar, .porfinalizar, .prAprobadas, .prospectosVerificados]

    /// Key into the per-category blocking days configured by the administrator.
    var claveBloqueo: String { rawValue }
}

struct MensajePredeterminado: Equatable {
    var saludo = ""
    var lugar = ""
    var cuerpo = ""
    var cuerpoMacro = ""
    var cuerpoLinea = ""
    var cuerpoFinancing = ""
    var cuerpoCreditos = ""
    var cuerpoFinancingAdv = ""
    var cuerpoCreditosAdv = ""
    var advFinancing = false
    var advCreditos = false

    init() {}

    init(_ json: JSON?) {
        saludo = json?["saludo"]?.text ?? ""
        lugar = json?["lugar"]?.text ?? ""
        cuerpo = json?["cuerpo"]?.text ?? ""
        cuerpoMacro = json?["cuerpoMacro"]?.text ?? ""
        cuerpoLinea = json?["cuerpoLinea"]?.text ?? ""
        cuerpoFinancing = json?["cuerpoFinancing"]?.text ?? ""
        cuerpoCreditos = json?["cuerpoCreditos"]?.text ?? ""
        cuerpoFinancingAdv = json?["cuerpoFinancingAdv"]?.text ?? ""
        cuerpoCreditosAdv = json?["cuerpoCreditosAdv"]?.text ?? ""
        advFinancing = json?["advFinancing"]?.truthy ?? false
        advCreditos = json?["advCreditos"]?.truthy ?? false
    }

    var tieneContenido: Bool {
        [saludo, lugar, cuerpo, cuerpoMacro, cuerpoLinea, cuerpoFinancing, cuerpoCreditos, cuerpoFinancingAdv, cuerpoCreditosAdv]
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var json: JSON {
        .object([
            "saludo": .string(saludo), "lugar": .string(lugar), "cuerpo": .string(cuerpo),
            "cuerpoMacro": .string(cuerpoMacro), "cuerpoLinea": .string(cuerpoLinea),
            "cuerpoFinancing": .string(cuerpoFinancing), "cuerpoCreditos": .string(cuerpoCreditos),
            "cuerpoFinancingAdv": .string(cuerpoFinancingAdv), "cuerpoCreditosAdv": .string(cuerpoCreditosAdv),
            "advFinancing": .bool(advFinancing), "advCreditos": .bool(advCreditos),
        ])
    }
}

/// Which body of a message template is added after the general one.
enum CuerpoMensaje: String {
    case promociones, macropesos, linea, financing, creditos, porfinalizar
}

struct ExtrasMensaje {
    var numPago = ""
    var lineaCredito: String?
    var enganche: String?
    var accesorioNombre: String?
    var accesorioPrecio: Double?
    var equipo = ""
    var tipoProducto = ""
    var modelo = ""
}

// MARK: - Building messages

/// Turns templates into WhatsApp text exactly as the web app does (`construirMensajeRec`,
/// `construirMensajePred`), including the bold client name and the cleanup of empty lines.
enum Mensajes {
    static func ordinal(_ numero: Int) -> String { "\(numero)°" }

    static func dinero(_ texto: String?) -> String {
        Dinero.texto(texto.flatMap { Double($0) } ?? 0)
    }

    static func recordatorio(_ plantilla: PlantillaRecordatorio, tipo: TipoRecordatorio, cliente: Cliente, extras: ExtrasMensaje = ExtrasMensaje()) -> String {
        let nombre = primerNombreApellido(cliente.nombre)
        let macro = cliente.macropesos ?? 0
        var cuerpo = plantilla.cuerpo
        var accesorio = "", precio = "", diferencia = ""
        if tipo == .macropesosDisponibles, plantilla.avanzadasActivas, let nombreAccesorio = extras.accesorioNombre, let precioAccesorio = extras.accesorioPrecio {
            cuerpo = plantilla.cuerpoAvanzado.isEmpty ? cuerpo : plantilla.cuerpoAvanzado
            accesorio = nombreAccesorio
            precio = String(Dinero.texto(precioAccesorio).dropFirst())
            let resto = max(0, precioAccesorio - macro)
            diferencia = resto > 0 ? Dinero.texto(resto) : "$0.00 (cubierto por tus macropesos)"
        }
        let linea = extras.lineaCredito.map(dinero) ?? ""
        let final = reemplazar(cuerpo, [
            "[nombre del cliente]": nombre,
            "[numero de pago]": extras.numPago,
            "[macropesos]": Dinero.texto(macro),
            "[linea de crédito]": linea,
            "[linea de credito]": linea,
            "[accesorio]": accesorio,
            "[precio accesorio]": precio,
            "[diferencia]": diferencia,
        ])
        return armar(saludo: plantilla.saludo, lugar: plantilla.lugar, nombre: nombre, cuerpos: [final])
    }

    static func predeterminado(_ plantilla: MensajePredeterminado, cliente: Cliente, cuerpo tipo: CuerpoMensaje, extras: ExtrasMensaje = ExtrasMensaje()) -> String {
        let extra: String
        switch tipo {
        case .promociones: extra = ""
        case .macropesos, .porfinalizar: extra = plantilla.cuerpoMacro
        case .linea: extra = plantilla.cuerpoLinea
        case .financing:
            extra = plantilla.advFinancing && !plantilla.cuerpoFinancingAdv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? plantilla.cuerpoFinancingAdv : plantilla.cuerpoFinancing
        case .creditos:
            extra = plantilla.advCreditos && !plantilla.cuerpoCreditosAdv.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? plantilla.cuerpoCreditosAdv : plantilla.cuerpoCreditos
        }

        let nombre = primerNombreApellido(cliente.nombre)
        let macro = cliente.macropesos ?? 0
        let linea = Dinero.texto(extras.lineaCredito.flatMap { Double($0) } ?? 0)
        let enganche = Dinero.texto(extras.enganche.flatMap { Double($0) } ?? 0)
        let producto = Mensajes.productos[extras.tipoProducto]?.singular ?? extras.tipoProducto

        func preparar(_ texto: String) -> String {
            var lineas = texto.components(separatedBy: "\n")
            // Without macropesos, lines that mention them are dropped.
            if macro <= 0 { lineas = lineas.filter { !contiene($0, "[macropesos]") } }
            lineas = lineas.filter { linea in
                if extras.equipo.isEmpty, contiene(linea, "[equipo]") { return false }
                if extras.tipoProducto.isEmpty, contiene(linea, "[tipo de producto]") { return false }
                if extras.modelo.isEmpty, contiene(linea, "[modelo]") { return false }
                if (extras.enganche ?? "").isEmpty, contiene(linea, "[enganche]") { return false }
                return true
            }
            let adaptado = adaptarArticulos(lineas.joined(separator: "\n"), producto: extras.tipoProducto)
            return reemplazar(adaptado, [
                "[nombre del cliente]": nombre,
                "[macropesos]": Dinero.texto(macro),
                "[linea de crédito]": linea,
                "[linea de credito]": linea,
                "[enganche]": enganche,
                "[equipo]": extras.equipo,
                "[tipo de producto]": producto,
                "[modelo]": extras.modelo,
            ])
        }
        return armar(saludo: plantilla.saludo, lugar: plantilla.lugar, nombre: nombre, cuerpos: [preparar(plantilla.cuerpo), preparar(extra)])
    }

    /// Greeting + bold name, place, then each non-empty body, separated by blank lines.
    static func armar(saludo: String, lugar: String, nombre: String, cuerpos: [String]) -> String {
        var partes = [saludo.trimmingCharacters(in: .whitespaces).isEmpty ? "*\(nombre)*" : "\(saludo)*\(nombre)*"]
        if !lugar.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { partes.append(lugar) }
        partes += cuerpos.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return partes.joined(separator: "\n\n")
    }

    static func reemplazar(_ texto: String, _ valores: [String: String]) -> String {
        valores.reduce(texto) { resultado, par in
            resultado.replacingOccurrences(of: par.key, with: par.value, options: .caseInsensitive)
        }
    }

    private static func contiene(_ texto: String, _ marcador: String) -> Bool {
        texto.range(of: marcador, options: .caseInsensitive) != nil
    }

    static let productos: [String: (singular: String, femenino: Bool)] = [
        "iPhone": ("iPhone", false),
        "Pantallas": ("pantalla", true),
        "Bicis": ("bici", true),
        "Motos": ("moto", true),
        "Accesorios": ("accesorio", false),
    ]

    /// Fixes the article right before "[tipo de producto]" to the product's gender ("el" → "la pantalla").
    static func adaptarArticulos(_ texto: String, producto: String) -> String {
        guard let info = productos[producto],
              let regex = try? NSRegularExpression(pattern: #"\b(el|la|los|las|un|una|unos|unas|al|del)(\s+\*?)\[tipo de producto\]"#, options: .caseInsensitive) else { return texto }
        let masculino = ["el": "el", "un": "un", "al": "al", "del": "del", "la": "el", "una": "un", "los": "el", "unos": "un", "las": "el", "unas": "un"]
        let femenino = ["el": "la", "un": "una", "al": "a la", "del": "de la", "la": "la", "una": "una", "los": "la", "unos": "una", "las": "la", "unas": "una"]
        let tabla = info.femenino ? femenino : masculino
        var resultado = texto
        let rango = NSRange(texto.startIndex..., in: texto)
        for coincidencia in regex.matches(in: texto, range: rango).reversed() {
            guard let total = Range(coincidencia.range, in: resultado),
                  let articuloRango = Range(coincidencia.range(at: 1), in: resultado),
                  let separadorRango = Range(coincidencia.range(at: 2), in: resultado) else { continue }
            let articulo = String(resultado[articuloRango])
            var nuevo = tabla[articulo.lowercased()] ?? articulo
            if let primera = articulo.first, primera.isUppercase { nuevo = nuevo.prefix(1).uppercased() + nuevo.dropFirst() }
            resultado.replaceSubrange(total, with: nuevo + resultado[separadorRango] + "[tipo de producto]")
        }
        return resultado
    }

    // MARK: Names

    private static let conectores: Set<String> = ["de", "del", "la", "las", "los", "y", "san", "santa", "da", "do", "di", "dos", "das"]

    /// First name (absorbing "de", "la"… so "María de Jesús" stays whole) and first surname, capitalized.
    static func partirNombre(_ completo: String) -> (nombre: String, apellido: String) {
        let partes = completo.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !partes.isEmpty else { return ("", "") }
        func capitalizar(_ token: String, _ posicion: Int) -> String {
            let minusculas = token.lowercased()
            if posicion > 0, conectores.contains(minusculas) { return minusculas }
            return minusculas.prefix(1).uppercased() + minusculas.dropFirst()
        }
        if partes.count == 1 { return (capitalizar(partes[0], 0), "") }
        func esConector(_ i: Int) -> Bool { conectores.contains(partes[i].lowercased()) }

        var i = 1
        while i < partes.count, esConector(i) {
            var salto = 1
            while i + salto < partes.count, esConector(i + salto) { salto += 1 }
            i += salto + 1
        }
        var j = i + 1
        while j < partes.count, esConector(j) {
            var salto = 1
            while j + salto < partes.count, esConector(j + salto) { salto += 1 }
            j += salto + 1
        }
        let nombre = partes[0..<min(i, partes.count)].enumerated().map { capitalizar($1, $0) }.joined(separator: " ")
        let apellido = i < partes.count ? partes[i..<min(j, partes.count)].enumerated().map { capitalizar($1, $0) }.joined(separator: " ") : ""
        return (nombre, apellido)
    }

    static func primerNombreApellido(_ completo: String) -> String {
        let partes = partirNombre(completo)
        return partes.apellido.isEmpty ? partes.nombre : partes.nombre + " " + partes.apellido
    }

    static func primerNombre(_ completo: String) -> String { partirNombre(completo).nombre }
}
