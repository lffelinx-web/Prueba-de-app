import SwiftUI

// MARK: - Shared fields

/// A "yyyy-MM-dd" date that may start empty.
struct CampoFecha: View {
    let titulo: String
    @Binding var texto: String

    var body: some View {
        if let fecha = Fecha.dia(texto) {
            DatePicker(titulo, selection: Binding(get: { fecha }, set: { texto = Fecha.iso($0) }), displayedComponents: .date)
                .environment(\.locale, Locale(identifier: "es_MX"))
        } else {
            Button {
                texto = Fecha.hoyISO
            } label: {
                LabeledContent(titulo) { Text("Seleccionar").foregroundStyle(.tint) }
            }
            .foregroundStyle(.primary)
        }
    }
}

struct CampoTelefono: View {
    let titulo: String
    @Binding var texto: String

    var body: some View {
        TextField(titulo, text: $texto)
            .keyboardType(.numberPad)
            .textContentType(.telephoneNumber)
            .onChange(of: texto) { _, nuevo in
                let limpio = String(Texto.soloDigitos(nuevo).prefix(10))
                if limpio != nuevo { texto = limpio }
            }
    }
}

/// "SL" or "PR" followed by up to 12 digits.
struct CampoFolio: View {
    let titulo: String
    let prefijo: String
    @Binding var texto: String

    var body: some View {
        TextField(titulo, text: $texto)
            .keyboardType(.numberPad)
            .font(.body.monospaced())
            .autocorrectionDisabled()
            .onChange(of: texto) { _, nuevo in
                var resto = nuevo.uppercased()
                if resto.hasPrefix(prefijo) { resto.removeFirst(prefijo.count) }
                let limpio = prefijo + String(Texto.soloDigitos(resto).prefix(12))
                if limpio != nuevo { texto = limpio }
            }
    }
}

struct SelectorAsesor: View {
    @EnvironmentObject private var store: Store
    let vacio: String
    let asignado: String?
    @Binding var asesor: String

    var body: some View {
        Picker("Asesor", selection: $asesor) {
            Text(vacio).tag("")
            ForEach(store.asesoresParaFormulario(asignado: asignado), id: \.self) { Text($0).tag($0) }
        }
        .disabled(!store.visibilidadCargada)
    }
}

private struct BarraFormulario: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let titulo: String
    let ocupado: Bool
    let guardar: () async -> Void

    func body(content: Content) -> some View {
        content
            .fondoTema()
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await guardar() } }
                        .bold()
                        .disabled(ocupado)
                }
            }
            .interactiveDismissDisabled(ocupado)
    }
}

private extension View {
    func barraFormulario(_ titulo: String, ocupado: Bool = false, guardar: @escaping () async -> Void) -> some View {
        modifier(BarraFormulario(titulo: titulo, ocupado: ocupado, guardar: guardar))
    }

    func errorFormulario(_ error: String) -> some View {
        safeAreaInset(edge: .bottom) {
            if !error.isEmpty {
                Text(error)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Paleta.peligro)
            }
        }
    }
}

// MARK: - Active client

struct FormularioActivo: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let clienteId: String?

    @StateObject private var flujo = AltaActivo()
    @State private var d = DatosActivo()
    @State private var ref1 = Referencia(nombre: "", tel: "")
    @State private var ref2 = Referencia(nombre: "", tel: "")
    @State private var cargado = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Datos del cliente") {
                    TextField("Nombre completo", text: $d.nombre)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                    CampoTelefono(titulo: "Teléfono (10 dígitos)", texto: $d.tel)
                    Toggle("¿Tiene WhatsApp?", isOn: $d.tieneWA)
                    CampoFecha(titulo: "Fecha de compra", texto: $d.compra)
                    CampoFolio(titulo: "SL — Solicitud conformada", prefijo: "SL", texto: $d.sl)
                    TextField("CURP (18 caracteres)", text: $d.curp)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: d.curp) { _, nuevo in
                            if nuevo.count > 18 { d.curp = String(nuevo.prefix(18)) }
                        }
                }
                Section("Crédito") {
                    Picker("Plazo (semanas)", selection: $d.semanas) {
                        Text("Seleccionar").tag("")
                        ForEach(Catalogos.plazos, id: \.self) { Text($0).tag($0) }
                    }
                    SelectorAsesor(vacio: "Seleccionar", asignado: store.cliente(clienteId)?.asesor, asesor: $d.asesor)
                    Picker("Tipo de crédito", selection: $d.tipo) {
                        Text("Seleccionar").tag("")
                        ForEach(Catalogos.tiposCredito, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Referencia personal 1") {
                    TextField("Nombre completo", text: $ref1.nombre).autocorrectionDisabled()
                    CampoTelefono(titulo: "Teléfono (10 dígitos)", texto: $ref1.tel)
                }
                Section("Referencia personal 2") {
                    TextField("Nombre completo", text: $ref2.nombre).autocorrectionDisabled()
                    CampoTelefono(titulo: "Teléfono (10 dígitos)", texto: $ref2.tel)
                }
            }
            .barraFormulario(clienteId == nil ? "Nuevo cliente" : "Editar cliente", ocupado: store.guardando) {
                var datos = d
                datos.id = clienteId
                datos.refs = [ref1, ref2]
                await flujo.iniciar(datos)
            }
            .errorFormulario(flujo.error)
            .sheet(item: $flujo.paso) { paso in
                PasoAltaView(paso: paso, flujo: flujo)
                    .capaDeEstado()
            }
        }
        .onAppear {
            flujo.usar(store)
            cargar()
        }
        .onChange(of: flujo.terminado) { _, terminado in
            if terminado { dismiss() }
        }
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        guard let c = store.cliente(clienteId) else { return }
        d.nombre = c.nombre
        d.tel = c.tel
        d.tieneWA = c["tieneWA"]?.truthy ?? true
        d.compra = c.fechaCompra ?? ""
        d.sl = c.sl ?? "SL"
        d.curp = c.curp ?? ""
        d.semanas = c.semanas ?? ""
        d.asesor = c.asesor ?? ""
        d.tipo = c.tipo ?? ""
        let refs = c.refs
        if refs.count > 0 { ref1 = refs[0] }
        if refs.count > 1 { ref2 = refs[1] }
    }
}

/// The questions asked while saving an active client.
struct PasoAltaView: View {
    @Environment(\.dismiss) private var dismiss
    let paso: PasoAlta
    @ObservedObject var flujo: AltaActivo
    @State private var eleccion: EleccionDatos?

    var body: some View {
        NavigationStack {
            List {
                switch paso {
                case .prospectosDuplicados(let items):
                    Section {
                        Text("\(items.count == 1 ? "Una de las referencias coincide" : "Algunas referencias coinciden") con un prospecto existente. Al continuar se \(items.count == 1 ? "inhabilitará el prospecto" : "inhabilitarán los prospectos") (ya no aparecerá\(items.count == 1 ? "" : "n") en esa sección) y la referencia se agregará al nuevo cliente activo.")
                            .font(.callout)
                    }
                    ForEach(items) { item in
                        Section("\(item.etiqueta) — prospecto encontrado") {
                            FilaDato("Nombre", item.prospecto.nombre)
                            FilaDato("Teléfono", item.prospecto.tel, monoespaciado: true)
                            if let origen = item.prospecto.origen { FilaDato("Origen", origen) }
                            if item.nombreReferencia != item.prospecto.nombre {
                                Text("⚠️ El nombre como referencia (\(item.nombreReferencia)) es distinto al del prospecto")
                                    .font(.footnote).foregroundStyle(Paleta.advertencia)
                            }
                        }
                    }
                    botones("Continuar", listo: true) { await flujo.absorberProspectos(items) }

                case .dobleFinanciamiento(let existente, let motivos, let telefonoDistinto):
                    Section {
                        Text(existente.categoria == .sinrenovar
                             ? "⚠️ Este cliente ya tuvo un crédito con nosotros (Sin renovar). Coincidencia por: \(motivos.joined(separator: ", "))."
                             : "⚠️ Este cliente ya tiene un crédito activo. Coincidencia por: \(motivos.joined(separator: ", ")).")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Paleta.advertencia)
                        FilaDato("Nombre", existente.nombre)
                        FilaDato("Teléfono", existente.tel)
                        FilaDato("SL", existente.sl, monoespaciado: true)
                        FilaDato("Compra", Fecha.corta(existente.fechaCompra))
                        FilaDato("Vence", Fecha.corta(existente.fechaFin))
                        FilaDato("Estatus", existente.estatus.titulo)
                    } footer: {
                        Text("¿Deseas confirmar el doble financiamiento? El crédito más reciente aparecerá en la tarjeta principal y el más antiguo quedará en \"Ver más\".")
                    }
                    if telefonoDistinto {
                        Section("¿Cuál es el teléfono actual?") {
                            opcion(.existente, existente.tel, "Teléfono del crédito anterior")
                            opcion(.nuevo, flujo.datosPendientes.tel, "Teléfono del nuevo crédito")
                        }
                    }
                    botones("Confirmar doble financiamiento", listo: !telefonoDistinto || eleccion != nil) {
                        await flujo.confirmarDobleFinanciamiento(telefono: telefonoDistinto ? eleccion : nil)
                    }

                case .coincidencia(let encontrado, let discrepancia):
                    Section {
                        FilaDato("Nombre", encontrado.nombre)
                        FilaDato("Teléfono", encontrado.tel)
                        if let sl = encontrado.sl { FilaDato("SL", sl, monoespaciado: true) }
                    } header: {
                        Text("Se encontró este cliente en \(encontrado.categoria?.titulo ?? encontrado.categoriaTexto)")
                    } footer: {
                        Text(accion(encontrado) + " ¿Deseas continuar?")
                    }
                    if let discrepancia {
                        let nuevo = flujo.datosPendientes
                        Section(tituloDiscrepancia(discrepancia)) {
                            switch discrepancia {
                            case .nombre:
                                opcion(.nuevo, nuevo.nombre, "Del nuevo crédito")
                                opcion(.existente, encontrado.nombre, "Del registro anterior")
                            case .tel:
                                opcion(.nuevo, nuevo.tel, "Del nuevo crédito")
                                opcion(.existente, encontrado.tel, "Del registro anterior")
                            case .ambos:
                                opcion(.nuevo, "\(nuevo.nombre) · \(nuevo.tel)", "Usar datos del nuevo crédito")
                                opcion(.existente, "\(encontrado.nombre) · \(encontrado.tel)", "Conservar datos del registro anterior")
                            }
                        }
                    }
                    botones("Continuar", listo: discrepancia == nil || eleccion != nil) {
                        await flujo.confirmarCoincidencia(encontrado, discrepancia: discrepancia, eleccion: eleccion)
                    }
                }
            }
            .fondoTema()
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        flujo.cancelar()
                        dismiss()
                    }
                }
            }
        }
    }

    private var titulo: String {
        switch paso {
        case .prospectosDuplicados: return "Referencia ya registrada"
        case .dobleFinanciamiento: return "Doble financiamiento"
        case .coincidencia(let encontrado, _): return "⚠️ Cliente en \(encontrado.categoria?.titulo ?? "")"
        }
    }

    private func accion(_ c: Cliente) -> String {
        switch c.categoria {
        case .sinrenovar?: return "El cliente pasará de Sin renovar a Activo. Su historial anterior quedará guardado."
        case .prospectos?: return "El cliente será inhabilitado en Prospectos."
        case .prAprobadas?: return "El cliente será eliminado de PR aprobada."
        case .prRechazadas?: return "El cliente será eliminado de PR rechazada."
        default: return ""
        }
    }

    private func tituloDiscrepancia(_ d: Discrepancia) -> String {
        switch d {
        case .nombre: return "El nombre no coincide. ¿Cuál es el correcto?"
        case .tel: return "El teléfono no coincide. ¿Cuál es el actual?"
        case .ambos: return "El nombre y teléfono no coinciden. ¿Cuáles son los datos correctos?"
        }
    }

    private func opcion(_ valor: EleccionDatos, _ texto: String, _ detalle: String) -> some View {
        Button {
            eleccion = valor
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(texto.isEmpty ? "—" : texto).foregroundStyle(.primary)
                    Text(detalle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: eleccion == valor ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.tint)
            }
        }
    }

    private func botones(_ titulo: String, listo: Bool, accion: @escaping () async -> Void) -> some View {
        Section {
            Button {
                Task { await accion() }
            } label: {
                Text(titulo).bold().frame(maxWidth: .infinity)
            }
            .disabled(!listo)
        }
    }
}

// MARK: - Prospect

struct FormularioProspecto: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let clienteId: String?

    @State private var d = DatosProspecto()
    @State private var esReferencia = false
    @State private var busqueda = ""
    @State private var error = ""
    @State private var cargado = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre completo", text: $d.nombre).autocorrectionDisabled()
                    CampoTelefono(titulo: "Teléfono (10 dígitos)", texto: $d.tel)
                    Toggle("¿Tiene WhatsApp?", isOn: $d.tieneWA)
                    CampoFecha(titulo: "Fecha de referencia", texto: $d.fecha)
                    SelectorAsesor(vacio: "Sin asignar", asignado: store.cliente(clienteId)?.asesor, asesor: $d.asesor)
                }
                Section {
                    Toggle("Verificado", isOn: $d.verificado)
                    Toggle("Inhabilitar", isOn: $d.inhabilitado)
                }
                Section {
                    Toggle("Es referencia de un cliente", isOn: $esReferencia)
                    if esReferencia {
                        if let titular = store.cliente(d.refDeId) {
                            HStack {
                                Label("\(titular.nombre) (\(titular.tel.isEmpty ? "—" : titular.tel))", systemImage: "link")
                                Spacer()
                                Button {
                                    d.refDeId = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        } else {
                            TextField("Buscar cliente activo o sin renovar", text: $busqueda)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                            ForEach(store.titularesPosibles(busqueda)) { c in
                                Button {
                                    d.refDeId = c.id
                                    busqueda = ""
                                    if d.asesor.isEmpty, let asesor = c.asesor { d.asesor = asesor }
                                } label: {
                                    VStack(alignment: .leading) {
                                        HStack {
                                            Text(c.nombre).foregroundStyle(.primary)
                                            Etiqueta(c.categoria == .sinrenovar ? "Sin renovar" : "Activo", color: c.categoria == .sinrenovar ? Paleta.doble : .accentColor)
                                        }
                                        Text("\(c.tel.isEmpty ? "—" : c.tel) · SL: \(c.sl ?? "—")").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .barraFormulario(clienteId == nil ? "Nuevo prospecto" : "Editar prospecto", ocupado: store.guardando) {
                var datos = d
                datos.id = clienteId
                if !esReferencia, store.cliente(clienteId)?.refDeId == nil { datos.refDeId = nil }
                switch await store.guardarProspecto(datos) {
                case .error(let mensaje): error = mensaje
                default: dismiss()
                }
            }
            .errorFormulario(error)
        }
        .onAppear(perform: cargar)
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        guard let c = store.cliente(clienteId) else { return }
        d.nombre = c.nombre
        d.tel = c.tel
        d.tieneWA = c["tieneWA"]?.truthy ?? true
        d.fecha = c.fechaRef ?? ""
        d.asesor = c.asesor ?? ""
        d.inhabilitado = c.inhabilitado
        d.verificado = c.verificado
        d.refDeId = c.refDeId
        esReferencia = c.refDeId != nil && store.cliente(c.refDeId) != nil
    }
}

// MARK: - PR

struct FormularioPR: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let categoria: Categoria
    let clienteId: String?

    @State private var d = DatosPR()
    @State private var error = ""
    @State private var candidatos: [CandidatoPR] = []
    @State private var pendiente: DatosPR?
    @State private var cargado = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre completo", text: $d.nombre).autocorrectionDisabled()
                    CampoTelefono(titulo: "Teléfono (10 dígitos)", texto: $d.tel)
                    Toggle("¿Tiene WhatsApp?", isOn: $d.tieneWA)
                }
                Section {
                    CampoFolio(titulo: "N° PR", prefijo: "PR", texto: $d.numPR)
                    SelectorAsesor(vacio: "Seleccionar", asignado: store.cliente(clienteId)?.asesor, asesor: $d.asesor)
                    CampoFecha(titulo: "Fecha de solicitud", texto: $d.fechaSolicitud)
                    Picker("Tipo", selection: $d.tipocred) {
                        Text("Seleccionar").tag("")
                        ForEach(Catalogos.tiposPR, id: \.self) { Text($0).tag($0) }
                    }
                }
                Section("Detalles") {
                    TextField("Detalles de la PR", text: $d.detalles, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .barraFormulario("\(clienteId == nil ? "Nueva" : "Editar") PR \(categoria == .prAprobadas ? "aprobada" : "rechazada")", ocupado: store.guardando) {
                var datos = d
                datos.id = clienteId
                datos.categoria = categoria
                switch await store.guardarPR(datos) {
                case .error(let mensaje): error = mensaje
                case .guardado: dismiss()
                case .candidatosPR(let lista, let datosLimpios):
                    error = ""
                    pendiente = datosLimpios
                    candidatos = lista
                }
            }
            .errorFormulario(error)
            .sheet(isPresented: Binding(get: { !candidatos.isEmpty }, set: { if !$0 { candidatos = [] } })) {
                coincidencias
                    .capaDeEstado()
            }
        }
        .onAppear(perform: cargar)
    }

    private var coincidencias: some View {
        NavigationStack {
            List {
                Section {
                    Text("Encontramos \(candidatos.count) cliente\(candidatos.count == 1 ? "" : "s") en Sin renovar que podría\(candidatos.count == 1 ? "" : "n") ser el mismo. Verifica los datos antes de continuar.")
                        .font(.callout)
                    FilaDato("Nombre capturado", pendiente?.nombre)
                    FilaDato("Teléfono capturado", pendiente?.tel)
                }
                ForEach(candidatos) { m in
                    Section {
                        FilaDato("Nombre", m.cliente.nombre)
                        FilaDato("Teléfono", m.cliente.tel)
                        if let sl = m.cliente.sl { FilaDato("SL", sl, monoespaciado: true) }
                        Button("Adjuntar PR a este cliente") {
                            guard let datos = pendiente else { return }
                            Task {
                                if await store.adjuntarPR(datos, a: m.cliente.id) {
                                    candidatos = []
                                    dismiss()
                                }
                            }
                        }
                        .bold()
                    } header: {
                        Text(m.coincideNombre && m.coincideTel ? "✓ Coincide nombre y teléfono" : m.coincideNombre ? "⚠️ Solo coincide nombre" : "⚠️ Solo coincide teléfono")
                    }
                }
                Section {
                    Button("Registrar como cliente nuevo en PR") {
                        guard let datos = pendiente else { return }
                        Task {
                            if case .guardado = await store.guardarPRNormal(datos) {
                                candidatos = []
                                dismiss()
                            }
                        }
                    }
                }
            }
            .fondoTema()
            .navigationTitle("Posible coincidencia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { candidatos = [] }
                }
            }
        }
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        d.categoria = categoria
        guard let c = store.cliente(clienteId) else { return }
        d.nombre = c.nombre
        d.tel = c.tel
        d.tieneWA = c["tieneWA"]?.truthy ?? true
        d.numPR = c.numPR ?? "PR"
        d.asesor = c.asesor ?? ""
        d.fechaSolicitud = c.fechaSolicitud ?? ""
        d.tipocred = c.tipocred ?? ""
        d.detalles = c.detallesPR ?? ""
    }
}

// MARK: - Fraud and follow-up

struct FormularioFraude: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let clienteId: String?

    @State private var d = DatosFraude()
    @State private var error = ""
    @State private var cargado = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre completo", text: $d.nombre).autocorrectionDisabled()
                CampoTelefono(titulo: "Teléfono", texto: $d.tel)
                TextField("CURP", text: $d.curp)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("Notas", text: $d.notas, axis: .vertical)
            }
            .barraFormulario(clienteId == nil ? "Nuevo registro de fraude" : "Editar fraude", ocupado: store.guardando) {
                var datos = d
                datos.id = clienteId
                switch await store.guardarFraude(datos) {
                case .error(let mensaje): error = mensaje
                default: dismiss()
                }
            }
            .errorFormulario(error)
        }
        .onAppear {
            guard !cargado else { return }
            cargado = true
            guard let c = store.cliente(clienteId) else { return }
            d = DatosFraude(id: c.id, nombre: c.nombre, tel: c.tel, curp: c.curp ?? "", notas: c.notas ?? "")
        }
    }
}

struct FormularioSeguimiento: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let clienteId: String

    @State private var tipo = ""
    @State private var notas = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Tipo de seguimiento", selection: $tipo) {
                    Text("Seleccionar").tag("")
                    ForEach(Seguimiento.tipos, id: \.self) { Text($0).tag($0) }
                }
                TextField("Notas", text: $notas, axis: .vertical)
                    .lineLimit(3...6)
            }
            .barraFormulario("Seguimiento", ocupado: store.guardando) {
                guard !tipo.isEmpty else {
                    error = "Selecciona el tipo de seguimiento."
                    return
                }
                if await store.guardarSeguimiento(clienteId, tipo: tipo, notas: notas) { dismiss() }
            }
            .errorFormulario(error)
        }
        .presentationDetents([.medium])
        .onAppear {
            if let seg = store.cliente(clienteId)?.seguimiento {
                tipo = seg.tipo
                notas = seg.notas
            }
        }
    }
}
