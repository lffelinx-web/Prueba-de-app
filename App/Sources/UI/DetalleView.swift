import SwiftUI

struct DetalleView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let clienteId: String

    @State private var confirmacion: Confirmacion?
    @State private var formulario: Formulario?
    @State private var macropesos = ""
    @State private var verHistorial = false
    @FocusState private var editandoMacro: Bool

    var body: some View {
        Group {
            if let c = store.cliente(clienteId) {
                contenido(c)
            } else {
                ContentUnavailableView("Registro no disponible", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .confirmacion($confirmacion)
        .formularios($formulario)
    }

    private func contenido(_ c: Cliente) -> some View {
        List {
            datos(c).seccionTema()
            if c.categoria == .activos || c.categoria == .sinrenovar {
                estatus(c).seccionTema()
                pagos(c).seccionTema()
                prAdjunta(c).seccionTema()
            }
            referencias(c).seccionTema()
            if let curp = c.curp, c.categoria == .activos || c.categoria == .sinrenovar || c.categoria == .fraude {
                Section("Código QR — CURP") {
                    VStack(spacing: 8) {
                        CodigoQR(texto: curp)
                        Text(curp).font(.caption.monospaced()).foregroundStyle(Tema.apagado)
                    }
                    .frame(maxWidth: .infinity)
                }
                .seccionTema()
            }
            if c.categoria == .activos || c.categoria == .sinrenovar {
                macro(c).seccionTema()
            }
            if c.categoria != .fraude, c.categoria != .prRechazadas {
                seguimiento(c).seccionTema()
            }
            otroFinanciamiento(c).seccionTema()
            acciones(c).seccionTema()
        }
        .fondoTema()
        .navigationTitle(c.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.esAdmin, let editar = Formulario.editar(c) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Editar") { formulario = editar }
                }
            }
        }
        .sheet(isPresented: $verHistorial) {
            HistorialView(cliente: c)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func datos(_ c: Cliente) -> some View {
        Section(c.categoria?.titulo ?? "Datos") {
            FilaDato("Teléfono", c.tel)
            FilaDato("WhatsApp", c.tieneWA ? "✓ Sí" : "✗ No")
            switch c.categoria {
            case .activos?, .sinrenovar?, .fraude?:
                FilaDato("SL", c.sl, monoespaciado: true)
                FilaDato("CURP", c.curp, monoespaciado: true)
                FilaDato("Asesor", c.asesor)
                FilaDato("Tipo de crédito", c.tipo)
                FilaDato("F. Compra", Fecha.corta(c.fechaCompra))
                FilaDato("Plazo", c.semanas.map { "\($0) semanas" })
                FilaDato("Fecha fin", Fecha.corta(c.fechaFin))
                if c.categoria == .fraude, let notas = c.notas { FilaDato("Notas", notas) }
            case .prospectos?:
                FilaDato("Origen", c.origen ?? "Manual")
                FilaDato("Fecha ref.", Fecha.corta(c.fechaRef))
                FilaDato("Asesor", c.asesor)
                FilaDato("Verificado", c.verificado ? "✓ Sí" : "No")
                if c.inhabilitado { FilaDato("Estado", "Inhabilitado") }
                if let titular = store.cliente(c.refDeId) {
                    NavigationLink(value: Ruta.cliente(titular.id)) {
                        LabeledContent("Referencia de", value: titular.nombre)
                    }
                }
            case .prAprobadas?, .prRechazadas?:
                FilaDato("N° PR", c.numPR, monoespaciado: true)
                FilaDato("Asesor", c.asesor)
                FilaDato("Fecha solicitud", Fecha.corta(c.fechaSolicitud))
                FilaDato("Tipo", c.tipocred)
                if let detalles = c.detallesPR { FilaDato("Detalles", detalles) }
                if let titular = store.cliente(c["clienteSinRenovarId"]?.text) {
                    NavigationLink(value: Ruta.cliente(titular.id)) {
                        LabeledContent("Cliente sin renovar", value: titular.nombre)
                    }
                }
            case nil:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func estatus(_ c: Cliente) -> some View {
        Section {
            Picker("Estatus del cliente", selection: Binding(get: { c.estatus }, set: { nuevo in
                confirmarEstatus(c, nuevo)
            })) {
                ForEach(Estatus.allCases) { Text($0.titulo).tag($0) }
            }
        }
    }

    @ViewBuilder
    private func pagos(_ c: Cliente) -> some View {
        let lista = c.pagos
        if !lista.isEmpty {
            Section("Seguimiento primeros 4 pagos") {
                HStack(alignment: .top) {
                    ForEach(lista, id: \.num) { pago in
                        let estado = c.estado(de: pago)
                        Button {
                            confirmarCambioPago(c, pago, estado)
                        } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(color(estado).opacity(estado == .pendiente ? 0.12 : 0.9))
                                        .frame(width: 42, height: 42)
                                    Text(estado == .pagado ? "✓" : estado == .noPagado ? "✗" : "\(pago.num)")
                                        .font(.headline)
                                        .foregroundStyle(estado == .pendiente ? Color.primary : Color.white)
                                }
                                Text(Fecha.corta(pago.fecha)).font(.caption2).foregroundStyle(.secondary)
                                Text(estado.titulo).font(.caption2.weight(.semibold)).foregroundStyle(color(estado))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
                let pasados = c.pagosPasadosSinConfirmar
                if !pasados.isEmpty {
                    Button("Confirmar pagos pasados (\(pasados.count))") {
                        store.revisarPagosDe = c.id
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func prAdjunta(_ c: Cliente) -> some View {
        if c.categoria == .sinrenovar, let pr = Reglas.prAdjuntaActiva(c) {
            let aprobada = pr["estatus"]?.text == "aprobada"
            Section {
                FilaDato("N° PR", pr["numPR"]?.text, monoespaciado: true)
                FilaDato("Tipo", pr["tipocred"]?.text)
                FilaDato("Asesor", pr["asesor"]?.text)
                FilaDato("Fecha solicitud", Fecha.corta(pr["fechaSolicitud"]?.text))
                if let detalles = pr["detallesPR"]?.text, !detalles.isEmpty {
                    Text(detalles).font(.footnote).foregroundStyle(.secondary)
                }
                let restantes = Reglas.diasRestantesPRAdjunta(pr)
                Text("⏱ Expira en \(restantes) día\(restantes == 1 ? "" : "s")").font(.footnote).foregroundStyle(.secondary)
                Button("Eliminar PR adjunta", role: .destructive) {
                    let tipo = aprobada ? "aprobada" : "rechazada"
                    confirmacion = Confirmacion(
                        titulo: "Eliminar PR adjunta",
                        mensaje: "¿Eliminar la PR \(tipo) \(pr["numPR"]?.text ?? "") de \(c.nombre)? Esto eliminará también el cliente vinculado en la sección de PR \(tipo)s.",
                        boton: "Eliminar", destructivo: true
                    ) { await store.eliminarPRAdjunta(c.id) }
                }
            } header: {
                Text(aprobada ? "✅ PR aprobada adjunta" : "❌ PR rechazada adjunta")
            }
        }
    }

    @ViewBuilder
    private func referencias(_ c: Cliente) -> some View {
        if c.categoria == .fraude {
            let refs = store.clientes.filter { $0.refDeId == c.id && $0.categoria == .fraude }
            if !refs.isEmpty {
                Section("Referencias vinculadas") {
                    ForEach(refs) { r in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(r.nombre)
                                Text(r.tel.isEmpty ? "Sin tel." : r.tel).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            BotonWhatsApp(cliente: r, compacto: true)
                        }
                    }
                }
            }
        } else if !c.refs.isEmpty {
            Section("Referencias personales") {
                ForEach(Array(c.refs.enumerated()), id: \.offset) { item in
                    let ref = item.element
                    HStack {
                        VStack(alignment: .leading) {
                            Text(ref.nombre.isEmpty ? "—" : ref.nombre)
                            Text(ref.tel.isEmpty ? "—" : ref.tel).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if c.tieneWA, !ref.tel.isEmpty, let url = WhatsApp.url(ref.tel) {
                            Link(destination: url) { Image(systemName: "message.fill") }
                                .buttonStyle(.bordered)
                                .tint(.green)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func macro(_ c: Cliente) -> some View {
        Section {
            HStack {
                Text("$")
                TextField("0.00", text: $macropesos)
                    .keyboardType(.decimalPad)
                    .focused($editandoMacro)
                if editandoMacro {
                    Button("Guardar") {
                        editandoMacro = false
                        let texto = macropesos.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                        if texto.isEmpty {
                            Task { await store.guardarMacropesos(c.id, valor: nil) }
                        } else if let valor = Double(texto) {
                            Task { await store.guardarMacropesos(c.id, valor: valor) }
                        } else {
                            store.avisar("Ingresa macropesos válidos: cero o un número positivo.", advertencia: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(Paleta.macro)
        } header: {
            Text("Macropesos")
        } footer: {
            Text("Última actualización: \(Fecha.actualizacion(c["macropesosFechaActualizacion"]?.text))")
        }
        .onAppear { macropesos = c.macropesos.map(formatoMacro) ?? "" }
        .onChange(of: c.macropesos) { _, nuevo in
            if !editandoMacro { macropesos = nuevo.map(formatoMacro) ?? "" }
        }
    }

    private func formatoMacro(_ valor: Double) -> String {
        valor.rounded() == valor ? String(Int(valor)) : String(valor)
    }

    @ViewBuilder
    private func seguimiento(_ c: Cliente) -> some View {
        Section("Seguimiento") {
            if let seg = c.seguimiento {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(seg.tipo) · \(Fecha.corta(seg.fecha))").font(.headline)
                    Text(seg.notas.isEmpty ? "Sin notas" : seg.notas).foregroundStyle(.secondary)
                }
                if store.esAdmin {
                    Button("Editar seguimiento") { formulario = .seguimiento(c.id) }
                    Button("Quitar seguimiento", role: .destructive) {
                        confirmacion = Confirmacion(titulo: "Quitar seguimiento", mensaje: "¿Quitar el seguimiento de \(c.nombre)?", boton: "Quitar", destructivo: true) {
                            await store.quitarSeguimiento(c.id)
                        }
                    }
                }
            } else if store.esAdmin {
                Button("Agregar seguimiento") { formulario = .seguimiento(c.id) }
            } else {
                Text("Sin seguimiento").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func otroFinanciamiento(_ c: Cliente) -> some View {
        if let otro = store.cliente(c.dobleFinId) {
            let vencido = otro.fechaFin.map { $0 <= Fecha.hoy } ?? false
            let liquidado = (vencido || otro.categoria == .sinrenovar) && otro.estatus != .atraso
            Section("↔ Otro financiamiento vinculado") {
                NavigationLink(value: Ruta.cliente(otro.id)) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(otro.nombre).font(.headline)
                            Spacer()
                            if otro.estatus == .atraso {
                                Etiqueta("En atraso", color: Paleta.advertencia)
                            } else if liquidado {
                                Etiqueta("✓ Liquidado", color: .blue)
                            } else {
                                Etiqueta("Al corriente", color: Paleta.exito)
                            }
                        }
                        Text(Reglas.esCreditoSecundario(otro, respectoA: c) ? "Crédito anterior" : "Crédito más reciente")
                            .font(.caption).foregroundStyle(Paleta.doble)
                        Text("\(otro.sl ?? "—") · Compra \(Fecha.corta(otro.fechaCompra)) · Vence \(Fecha.corta(otro.fechaFin))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func acciones(_ c: Cliente) -> some View {
        Section {
            if c.tieneTelefonoWA, let url = WhatsApp.url(c.tel) {
                Link(destination: url) { Label("WhatsApp", systemImage: "message.fill") }
                    .foregroundStyle(.green)
            }
            if !c.historial.isEmpty {
                Button {
                    verHistorial = true
                } label: {
                    Label("Ver historial (\(c.historial.count) crédito\(c.historial.count == 1 ? "" : "s") anterior\(c.historial.count == 1 ? "" : "es"))", systemImage: "clock.arrow.circlepath")
                }
            }
            if store.esAdmin, c.categoria == .activos, let restantes = c.semanasRestantes, (0...5).contains(restantes) {
                Button {
                    confirmacion = Confirmacion(
                        titulo: "⚡ Liquidación anticipada",
                        mensaje: "¿Confirmar la liquidación anticipada de \(c.nombre)? El cliente pasará a \"Sin renovar\" inmediatamente (faltaban \(restantes) semana\(restantes == 1 ? "" : "s")).",
                        boton: "Liquidar"
                    ) { await store.liquidacionAnticipada(c.id) }
                } label: {
                    Label("Liquidación anticipada (\(restantes) sem. restante\(restantes == 1 ? "" : "s"))", systemImage: "bolt.fill")
                }
                .foregroundStyle(Paleta.advertencia)
            }
            if store.esAdmin, c.categoria == .sinrenovar {
                Button(c.suspendido ? "Reactivar cliente" : "Suspender cliente") {
                    Task { await store.alternarSuspension(c.id) }
                }
            }
            if store.esAdmin {
                Button("Eliminar registro", role: .destructive) {
                    let refs = [.activos, .sinrenovar, .fraude].contains(c.categoria) && store.tieneReferenciasVinculadas(c.id)
                    var mensaje = "¿Eliminar \(c.nombre)?"
                    if refs { mensaje += " Sus referencias vinculadas también serán eliminadas." }
                    if c.dobleFinId != nil { mensaje += " El vínculo de doble financiamiento también se eliminará." }
                    confirmacion = Confirmacion(titulo: "Eliminar registro", mensaje: mensaje, boton: "Eliminar", destructivo: true) {
                        await store.eliminar(c.id)
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func color(_ estado: EstadoPago) -> Color {
        switch estado {
        case .pagado: return Paleta.exito
        case .noPagado: return Paleta.peligro
        case .hoy: return Paleta.advertencia
        case .pendiente: return .secondary
        }
    }

    private func confirmarEstatus(_ c: Cliente, _ nuevo: Estatus) {
        guard nuevo != c.estatus else { return }
        confirmacion = Confirmacion(
            titulo: "Cambiar estatus",
            mensaje: "¿Cambiar el estatus de \(c.nombre) a \(nuevo.titulo)?",
            boton: "Cambiar",
            destructivo: nuevo == .fraude
        ) { await store.cambiarEstatus(de: c.id, a: nuevo) }
    }

    private func confirmarCambioPago(_ c: Cliente, _ pago: Pago, _ estado: EstadoPago) {
        switch estado {
        case .pagado, .noPagado:
            confirmacion = Confirmacion(
                titulo: estado == .pagado ? "Revertir pago" : "Revertir a pendiente",
                mensaje: "¿Marcar el pago \(pago.num) de 4 de \(c.nombre) como pendiente nuevamente?",
                boton: "Revertir"
            ) { await store.revertirPago(pago.num, de: c.id) }
        case .hoy, .pendiente:
            confirmacion = Confirmacion(
                titulo: "Confirmar pago",
                mensaje: "¿Confirmar el pago \(pago.num) de 4 de \(c.nombre)?",
                boton: "Confirmar"
            ) { await store.confirmarPagos([pago.num], de: c.id) }
        }
    }
}

struct HistorialView: View {
    @Environment(\.dismiss) private var dismiss
    let cliente: Cliente

    var body: some View {
        let creditos = cliente.historial.sorted { ($0["fechaCompra"]?.text ?? "") > ($1["fechaCompra"]?.text ?? "") }
        NavigationStack {
            List {
                ForEach(Array(creditos.enumerated()), id: \.offset) { item in
                    let n = item.offset
                    let h = item.element
                    Section {
                        FilaDato("SL", h["sl"]?.text, monoespaciado: true)
                        FilaDato("Asesor", h["asesor"]?.text)
                        FilaDato("Tipo", h["tipo"]?.text)
                        FilaDato("F. Compra", Fecha.corta(h["fechaCompra"]?.text))
                        FilaDato("Plazo", h["semanas"]?.text.map { "\($0) semanas" })
                        FilaDato("F. Fin", Fecha.corta(h["fechaFin"]?.text))
                        ForEach(Array((h["refs"]?.list ?? []).enumerated()), id: \.offset) { item in
                            let r = item.element
                            LabeledContent("Referencia", value: "\(r["nombre"]?.text ?? "—") · \(r["tel"]?.text ?? "—")")
                        }
                    } header: {
                        HStack {
                            Text("Crédito #\(creditos.count - n)")
                            Spacer()
                            if h["estatus"]?.text == "atraso" {
                                Etiqueta("Finalizó en atraso", color: Paleta.advertencia)
                            } else {
                                Etiqueta("✓ Liquidado", color: .blue)
                            }
                        }
                    }
                }
            }
            .fondoTema()
            .navigationTitle("Historial — \(cliente.nombre)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }
}

/// Past payments of a client, to confirm one by one or all together.
struct PagosPasadosView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let clienteId: String
    @State private var confirmacion: Confirmacion?

    var body: some View {
        NavigationStack {
            List {
                if let c = store.cliente(clienteId) {
                    let pasados = c.pagosPasadosSinConfirmar
                    if pasados.isEmpty {
                        Label("Todos los pagos pasados confirmados", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Paleta.exito)
                    } else {
                        Section {
                            ForEach(pasados, id: \.num) { pago in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Pago \(pago.num) de 4")
                                        Text(Fecha.corta(pago.fecha)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Confirmar") {
                                        confirmacion = Confirmacion(titulo: "Confirmar pago", mensaje: "¿Confirmar el pago \(pago.num) de 4 de \(c.nombre)?", boton: "Confirmar") {
                                            await store.confirmarPagos([pago.num], de: c.id)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                        } header: {
                            Text("Los siguientes pagos ya pasaron. ¿Fueron realizados?")
                        }
                    }
                }
            }
            .fondoTema()
            .navigationTitle("Confirmar pagos pasados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .confirmacion($confirmacion)
        }
        .capaDeEstado()
    }
}
