import SwiftUI

struct BaseDatosView: View {
    @EnvironmentObject private var store: Store

    private let columnas = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columnas, spacing: 12) {
                ForEach(Categoria.allCases) { categoria in
                    NavigationLink(value: Ruta.categoria(categoria)) {
                        VStack(spacing: 8) {
                            IconoCuadro(sistema: categoria.icono, color: color(categoria), lado: 44)
                            Text(categoria.titulo)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Tema.texto)
                                .multilineTextAlignment(.center)
                            Text("\(Reglas.conteo(categoria, en: store.clientes)) reg.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Tema.apagado)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Tema.superficie, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tema.borde, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Tema.fondo)
        .navigationTitle("Base de datos")
        .conNotificaciones()
        .overlay {
            if !store.clientesCargados { ProgressView() }
        }
    }

    private func color(_ categoria: Categoria) -> Color {
        switch categoria {
        case .activos: return Tema.acento
        case .sinrenovar: return Paleta.doble
        case .prospectos: return Tema.info
        case .prAprobadas: return Paleta.exito
        case .prRechazadas: return Paleta.peligro
        case .fraude: return Paleta.advertencia
        }
    }
}

/// Forms opened from lists and details.
enum Formulario: Identifiable {
    case activo(String?)
    case prospecto(String?)
    case pr(Categoria, String?)
    case fraude(String?)
    case seguimiento(String)

    var id: String {
        switch self {
        case .activo(let id): return "activo-" + (id ?? "nuevo")
        case .prospecto(let id): return "prospecto-" + (id ?? "nuevo")
        case .pr(let categoria, let id): return "pr-\(categoria.rawValue)-" + (id ?? "nuevo")
        case .fraude(let id): return "fraude-" + (id ?? "nuevo")
        case .seguimiento(let id): return "seguimiento-" + id
        }
    }

    static func editar(_ c: Cliente) -> Formulario? {
        switch c.categoria {
        case .activos?, .sinrenovar?: return .activo(c.id)
        case .prospectos?: return .prospecto(c.id)
        case .prAprobadas?, .prRechazadas?: return .pr(c.categoria!, c.id)
        case .fraude?: return .fraude(c.id)
        case nil: return nil
        }
    }

    static func nuevo(_ categoria: Categoria) -> Formulario? {
        switch categoria {
        case .activos: return .activo(nil)
        case .prospectos: return .prospecto(nil)
        case .prAprobadas, .prRechazadas: return .pr(categoria, nil)
        case .fraude: return .fraude(nil)
        case .sinrenovar: return nil
        }
    }
}

extension View {
    func formularios(_ formulario: Binding<Formulario?>) -> some View {
        sheet(item: formulario) { formulario in
            Group {
                switch formulario {
                case .activo(let id): FormularioActivo(clienteId: id)
                case .prospecto(let id): FormularioProspecto(clienteId: id)
                case .pr(let categoria, let id): FormularioPR(categoria: categoria, clienteId: id)
                case .fraude(let id): FormularioFraude(clienteId: id)
                case .seguimiento(let id): FormularioSeguimiento(clienteId: id)
                }
            }
            .capaDeEstado()
        }
    }
}

struct CategoriaView: View {
    @EnvironmentObject private var store: Store
    let categoria: Categoria

    @State private var busqueda = ""
    @State private var filtros = Filtros()
    @State private var mostrarFiltros = false
    @State private var formulario: Formulario?
    @State private var confirmacion: Confirmacion?
    @State private var revision: Reglas.Duplicado?

    var body: some View {
        let lista = Reglas.lista(categoria, en: store.clientes, busqueda: busqueda, filtros: filtros)
        let duplicados = Reglas.duplicados(categoria, en: store.clientes)

        List {
            if !duplicados.isEmpty {
                Section {
                    ForEach(duplicados) { par in
                        HStack {
                            Text("⚠️ " + par.mensaje).font(.footnote).foregroundStyle(Tema.advertencia)
                            Spacer()
                            Button("Revisar") { revision = par }
                                .buttonStyle(.pastilla(Tema.advertencia))
                        }
                        .tarjeta(borde: Tema.advertencia.opacity(0.5))
                        .filaTarjeta()
                    }
                }
            }
            if lista.isEmpty {
                ContentUnavailableView(busqueda.isEmpty ? "Sin registros" : "Sin resultados", systemImage: categoria.icono)
                    .filaTarjeta()
            }
            ForEach(lista) { c in
                EnlaceSinFlecha(valor: .cliente(c.id)) {
                    FilaCliente(cliente: c)
                }
                .filaTarjeta()
                .swipeActions(edge: .trailing) {
                    if store.esAdmin {
                        Button(role: .destructive) {
                            confirmarEliminar(c)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                        if let editar = Formulario.editar(c) {
                            Button {
                                formulario = editar
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            .tint(.accentColor)
                        }
                    }
                }
                .swipeActions(edge: .leading) {
                    if store.esAdmin, categoria == .sinrenovar {
                        Button {
                            confirmarSuspension(c)
                        } label: {
                            Label(c.suspendido ? "Reactivar" : "Suspender", systemImage: c.suspendido ? "play.fill" : "pause.fill")
                        }
                        .tint(Paleta.advertencia)
                    }
                    if store.esAdmin, [.prospectos, .prAprobadas].contains(categoria) {
                        Button {
                            formulario = .seguimiento(c.id)
                        } label: {
                            Label("Seguimiento", systemImage: "list.clipboard")
                        }
                        .tint(Paleta.doble)
                    }
                }
            }
        }
        .listStyle(.plain)
        .fondoTema()
        .navigationTitle(categoria.titulo)
        .searchable(text: $busqueda, prompt: "Buscar nombre, teléfono, SL o PR")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar {
            if Filtros.filtrables.contains(categoria) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        mostrarFiltros = true
                    } label: {
                        Label("Filtros", systemImage: filtros.cantidad > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            if store.esAdmin, let nuevo = Formulario.nuevo(categoria) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        formulario = nuevo
                    } label: {
                        Label("Agregar", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $mostrarFiltros) {
            FiltrosView(categoria: categoria, filtros: $filtros)
        }
        .sheet(item: $revision) { par in
            RevisionDuplicadoView(idA: par.a.id, idB: par.b.id)
                .capaDeEstado()
        }
        .formularios($formulario)
        .confirmacion($confirmacion)
    }

    private func confirmarEliminar(_ c: Cliente) {
        let refs = [.activos, .sinrenovar, .fraude].contains(c.categoria) && store.tieneReferenciasVinculadas(c.id)
        var mensaje = "¿Eliminar \(c.nombre)?"
        if refs { mensaje += " Sus referencias vinculadas también serán eliminadas." }
        if c.dobleFinId != nil { mensaje += " El vínculo de doble financiamiento también se eliminará." }
        confirmacion = Confirmacion(titulo: "Eliminar registro", mensaje: mensaje, boton: "Eliminar", destructivo: true) {
            await store.eliminar(c.id)
        }
    }

    private func confirmarSuspension(_ c: Cliente) {
        confirmacion = Confirmacion(
            titulo: c.suspendido ? "Reactivar cliente" : "Suspender cliente",
            mensaje: c.suspendido
                ? "¿Reactivar a \(c.nombre)? Volverá a aparecer en mensajes y recordatorios."
                : "¿Suspender a \(c.nombre)? No aparecerá en mensajes, recordatorios ni listas mientras esté suspendido.",
            boton: c.suspendido ? "Reactivar" : "Suspender"
        ) {
            await store.alternarSuspension(c.id)
        }
    }
}

/// One card in a category list, with what matters for that category.
struct FilaCliente: View {
    @EnvironmentObject private var store: Store
    let cliente: Cliente

    var body: some View {
        let c = cliente
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                NombreCliente(nombre: c.nombre, apagado: c.inhabilitado)
                if c.dobleFinId != nil, c.categoria == .activos { Etiqueta("2 créditos", color: Paleta.doble) }
                Spacer(minLength: 4)
                etiquetas
            }
            switch c.categoria {
            case .activos?:
                datos(c.sl, izquierda: "Compra \(Fecha.corta(c.fechaCompra))", derecha: c.macropesos.map { "💰 " + Dinero.texto($0) }, colorDerecha: Tema.acento)
            case .sinrenovar?:
                datos(c.sl, izquierda: c.asesor ?? "Sin asesor", derecha: "Vence \(Fecha.corta(c.fechaFin))")
                if let pr = Reglas.prAdjuntaActiva(c) {
                    Text("📋 \(pr["numPR"]?.text ?? "—") · \(pr["tipocred"]?.text ?? "—")")
                        .font(Tipo.detalle.monospaced())
                        .foregroundStyle(Tema.apagado)
                }
            case .prospectos?:
                if !c.inhabilitado {
                    datos(nil, izquierda: "Ref. \(Fecha.corta(c.fechaRef)) · \(c.asesor ?? "Sin asesor")", derecha: c.origen ?? "Manual")
                }
            case .prAprobadas?, .prRechazadas?:
                let restantes = diasRestantesPR(c)
                datos(c.numPR, izquierda: "\(c.asesor ?? "—") · \(c.tipocred ?? "—")", derecha: "\(restantes) días", colorDerecha: restantes <= 5 ? Tema.peligro : Tema.apagado)
                if let detalles = c.detallesPR {
                    Text(detalles).font(Tipo.detalle).foregroundStyle(Tema.apagado).lineLimit(2)
                }
            case .fraude?:
                datos(c.sl, izquierda: "\(Fecha.corta(c.fechaCompra)) · \(c.tipo ?? "—")", derecha: nil)
            case nil:
                EmptyView()
            }
        }
        .tarjeta(borde: resaltado ?? Tema.borde, fondo: resaltado.map { $0.opacity(0.08) } ?? Tema.superficie)
    }

    /// Late clients get the web's yellow card; suspended "sin renovar" ones a softer one.
    private var resaltado: Color? {
        let c = cliente
        if c.categoria == .sinrenovar, c.suspendido { return Paleta.advertencia.opacity(0.6) }
        if (c.categoria == .activos || c.categoria == .prospectos), enAtraso { return Paleta.advertencia }
        return nil
    }

    private var otroCredito: Cliente? { store.cliente(cliente.dobleFinId) }

    private var enAtraso: Bool {
        cliente.estatus == .atraso || (cliente.categoria == .activos && otroCredito?.estatus == .atraso)
    }

    @ViewBuilder
    private var etiquetas: some View {
        let c = cliente
        switch c.categoria {
        case .activos?:
            if otroCredito?.estatus == .atraso, c.estatus != .atraso {
                Etiqueta("Otro en atraso", color: Paleta.advertencia)
            } else {
                EtiquetaEstatus(estatus: c.estatus)
            }
        case .sinrenovar?:
            if c.suspendido {
                Etiqueta("⏸ Suspendido", color: Paleta.advertencia)
            } else if let pr = Reglas.prAdjuntaActiva(c) {
                pr["estatus"]?.text == "aprobada" ? Etiqueta("Con PR aprobada", color: Paleta.exito) : Etiqueta("Con PR rechazada", color: Paleta.peligro)
            } else {
                Etiqueta("Sin renovar", color: Paleta.doble)
            }
        case .prospectos?:
            if c.inhabilitado {
                Etiqueta("Inhabilitado")
            } else {
                HStack(spacing: 4) {
                    if c.verificado { Etiqueta("✓", color: Paleta.exito) }
                    if c.esPRAprobada { Etiqueta("PR aprobada", color: Paleta.exito) }
                    if c.seguimiento != nil { Etiqueta("Seg.", color: Paleta.doble) }
                    if c.estatus == .atraso { Etiqueta("Atraso", color: Paleta.advertencia) }
                }
            }
        case .prAprobadas?:
            Etiqueta("Aprobada", color: Paleta.exito)
        case .prRechazadas?:
            Etiqueta("Rechazada", color: Paleta.peligro)
        case .fraude?:
            Etiqueta("Fraude", color: Paleta.peligro)
        case nil:
            EmptyView()
        }
    }

    private func diasRestantesPR(_ c: Cliente) -> Int {
        let base = Fecha.dia(c.fechaSolicitud) ?? Fecha.dia(c.fechaIngresoPR)
        let dias = base.map { Fecha.dias(desde: $0, hasta: Fecha.hoy) } ?? 0
        return (c.categoria == .prAprobadas ? 30 : 90) - dias
    }

    /// Phone and folio on the first line, then a detail on the left and a highlighted value on the right.
    private func datos(_ folio: String?, izquierda: String, derecha: String?, colorDerecha: Color = Tema.apagado) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                LineaTelefono(tel: cliente.tel)
                Spacer(minLength: 4)
                if let folio { ChipSL(folio) }
            }
            HStack(spacing: 8) {
                Text(izquierda).font(Tipo.detalle).foregroundStyle(Tema.apagado).lineLimit(1)
                Spacer(minLength: 4)
                if let derecha {
                    Text(derecha).font(Tipo.detalle.weight(.semibold)).foregroundStyle(colorDerecha).lineLimit(1).fixedSize()
                }
            }
        }
    }
}

struct FiltrosView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let categoria: Categoria
    @Binding var filtros: Filtros
    @State private var borrador = Filtros()

    var body: some View {
        NavigationStack {
            Form {
                Picker("Asesor", selection: $borrador.asesor) {
                    Text("Todos").tag("")
                    ForEach(store.asesores, id: \.self) { Text($0).tag($0) }
                }
                switch categoria {
                case .prospectos:
                    Picker("Tipo", selection: $borrador.tipoProspecto) {
                        Text("Todos").tag("")
                        Text("PR aprobada").tag("pr-aprobada")
                        Text("Prospecto normal").tag("normal")
                    }
                    Picker("Verificación", selection: $borrador.verificado) {
                        Text("Todos").tag("")
                        Text("Verificados").tag("si")
                        Text("No verificados").tag("no")
                    }
                    Picker("WhatsApp", selection: $borrador.whatsapp) {
                        Text("Todos").tag("")
                        Text("Con WhatsApp").tag("si")
                        Text("Sin WhatsApp").tag("no")
                    }
                    rango("Fecha ref.", desde: $borrador.fechaDesde, hasta: $borrador.fechaHasta)
                case .prAprobadas:
                    Picker("Tipo", selection: $borrador.tipocred) {
                        Text("Todos").tag("")
                        ForEach(Catalogos.tiposPR, id: \.self) { Text($0).tag($0) }
                    }
                    rango("Fecha solicitud", desde: $borrador.fechaDesde, hasta: $borrador.fechaHasta)
                default:
                    Picker("Tipo de crédito", selection: $borrador.tipo) {
                        Text("Todos").tag("")
                        ForEach(Catalogos.tiposCredito, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Plazo (semanas)", selection: $borrador.plazo) {
                        Text("Todos").tag("")
                        ForEach(Catalogos.plazos, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Estatus", selection: $borrador.estatus) {
                        Text("Todos").tag("")
                        Text("Al corriente").tag(Estatus.alCorriente.rawValue)
                        Text("En atraso").tag(Estatus.atraso.rawValue)
                    }
                    rango("F. compra", desde: $borrador.compraDesde, hasta: $borrador.compraHasta)
                    rango("F. vencimiento", desde: $borrador.venceDesde, hasta: $borrador.venceHasta)
                    Section("Macropesos") {
                        TextField("Mínimo ($)", text: $borrador.macroMin).keyboardType(.decimalPad)
                        TextField("Máximo ($)", text: $borrador.macroMax).keyboardType(.decimalPad)
                    }
                }
            }
            .fondoTema()
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Limpiar") {
                        filtros = Filtros()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        filtros = borrador
                        dismiss()
                    }
                }
            }
            .onAppear { borrador = filtros }
        }
        .presentationDetents([.medium, .large])
    }

    private func rango(_ titulo: String, desde: Binding<Date?>, hasta: Binding<Date?>) -> some View {
        Section(titulo) {
            FechaOpcional(titulo: "Desde", fecha: desde)
            FechaOpcional(titulo: "Hasta", fecha: hasta)
        }
    }
}

/// A date that can be left empty.
struct FechaOpcional: View {
    let titulo: String
    @Binding var fecha: Date?

    var body: some View {
        if let valor = fecha {
            HStack {
                DatePicker(titulo, selection: Binding(get: { valor }, set: { fecha = $0 }), displayedComponents: .date)
                Button {
                    fecha = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        } else {
            Button {
                fecha = Fecha.hoy
            } label: {
                LabeledContent(titulo) { Text("Cualquiera").foregroundStyle(.secondary) }
            }
            .foregroundStyle(.primary)
        }
    }
}

/// Two prospects that look like the same person; disable one of them.
struct RevisionDuplicadoView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let idA: String
    let idB: String

    var body: some View {
        NavigationStack {
            List {
                ForEach([idA, idB], id: \.self) { id in
                    if let c = store.cliente(id) {
                        Section {
                            FilaDato("Teléfono", c.tel)
                            FilaDato("Fecha ref.", c.fechaRef)
                            FilaDato("Asesor", c.asesor ?? "Sin asesor")
                            FilaDato("Referencia de", store.cliente(c.refDeId)?.nombre)
                            FilaDato("Origen", c.origen ?? "Manual")
                            if store.esAdmin {
                                Button(c.inhabilitado ? "Reactivar" : "Inhabilitar este", role: c.inhabilitado ? nil : .destructive) {
                                    Task { await store.cambiarInhabilitado(id, !c.inhabilitado) }
                                }
                            }
                        } header: {
                            Text(c.nombre + (c.inhabilitado ? " (inhabilitado)" : ""))
                        }
                    }
                }
            }
            .navigationTitle("Posible duplicado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }
}
