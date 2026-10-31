import SwiftUI

struct DetalleView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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

    private func esCredito(_ c: Cliente) -> Bool { c.categoria == .activos || c.categoria == .sinrenovar }

    private func contenido(_ c: Cliente) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                cabecera(c)
                if esCredito(c) {
                    indicadores(c)
                    pagos(c)
                }
                datos(c)
                prAdjunta(c)
                referencias(c)
                if esCredito(c) { macro(c) }
                if c.categoria != .fraude, c.categoria != .prRechazadas { seguimiento(c) }
                otroFinanciamiento(c)
                acciones(c)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Tema.fondo)
        .navigationTitle(c.categoria?.titulo ?? "Cliente")
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

    // MARK: - Building blocks

    private func tarjeta<Accesorio: View, Contenido: View>(_ titulo: String, @ViewBuilder accesorio: () -> Accesorio, @ViewBuilder contenido: () -> Contenido) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(titulo).font(.system(size: 15, weight: .bold)).foregroundStyle(Tema.texto)
                Spacer(minLength: 6)
                accesorio()
            }
            contenido()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.superficie, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Tema.borde, lineWidth: 1))
    }

    private func tarjeta<Contenido: View>(_ titulo: String, @ViewBuilder contenido: () -> Contenido) -> some View {
        tarjeta(titulo, accesorio: { EmptyView() }, contenido: contenido)
    }

    private func campo(_ titulo: String, _ valor: String?, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titulo.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Tema.apagado)
            Text((valor?.isEmpty ?? true) ? "—" : valor!)
                .font(mono ? .system(size: 14, weight: .semibold, design: .monospaced) : .system(size: 14, weight: .semibold))
                .foregroundStyle(Tema.texto)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func color(de c: Cliente) -> Color {
        c.categoria.map(BaseDatosView.color) ?? Tema.Seccion.azul
    }

    // MARK: - Header

    private func cabecera(_ c: Cliente) -> some View {
        let tono = color(de: c)
        let iniciales = String(c.nombre.split(separator: " ").compactMap(\.first).prefix(2)).uppercased()
        return VStack(spacing: 10) {
            Text(iniciales.isEmpty ? "?" : iniciales)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 68, height: 68)
                .background(Circle().fill(tono).overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.38), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))))
                .shadow(color: tono.opacity(0.45), radius: 10, x: 0, y: 6)
            Text(c.nombre)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(c.inhabilitado ? Tema.apagado : Tema.texto)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack(spacing: 6) {
                if esCredito(c) {
                    EtiquetaEstatus(estatus: c.estatus)
                } else if let categoria = c.categoria {
                    Etiqueta(categoria.titulo, color: tono)
                }
                if c.inhabilitado { Etiqueta("Inhabilitado") }
                if c.suspendido { Etiqueta("Suspendido", color: Tema.advertencia) }
                if let folio = c.sl ?? c.numPR { ChipCopiable(texto: folio, etiqueta: c.sl != nil ? "SL" : "PR") }
            }
            HStack(spacing: 8) {
                accionRapida("Llamar", icono: "phone.fill", fondo: Tema.acento.opacity(0.12), texto: Tema.acento) {
                    if let url = URL(string: "tel://" + Texto.soloDigitos(c.tel)), !c.tel.isEmpty { openURL(url) }
                }
                .disabled(c.tel.isEmpty)
                accionRapida("WhatsApp", icono: "message.fill", fondo: Tema.Seccion.whatsapp, texto: .white) {
                    if let url = WhatsApp.url(c.tel) { openURL(url) }
                }
                .disabled(!c.tieneTelefonoWA)
                .opacity(c.tieneTelefonoWA ? 1 : 0.45)
                if store.esAdmin, c.categoria != .fraude, c.categoria != .prRechazadas {
                    accionRapida("Seguimiento", icono: "list.clipboard.fill", fondo: Tema.morado.opacity(0.14), texto: Tema.Seccion.morado) {
                        formulario = .seguimiento(c.id)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Tema.superficie, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Tema.borde, lineWidth: 1))
    }

    private func accionRapida(_ titulo: String, icono: String, fondo: Color, texto: Color, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(spacing: 4) {
                Image(systemName: icono).font(.system(size: 17, weight: .semibold))
                Text(titulo).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(texto)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(fondo, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Credit

    private func indicadores(_ c: Cliente) -> some View {
        HStack(spacing: 8) {
            indicador("Restan", valor: c.semanasRestantes.map { "\(max(0, $0))" } ?? "—", unidad: "sem")
            indicador("Pagos", valor: "\(c.pagosConfirmados.filter { (1...4).contains($0) }.count)", unidad: "/4")
            indicador("Macropesos", valor: c.macropesos.map { Dinero.texto($0) } ?? "$0", unidad: nil, color: Tema.acento)
        }
    }

    private func indicador(_ titulo: String, valor: String, unidad: String?, color: Color = Tema.texto) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo.uppercased()).font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Tema.apagado)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valor).font(.system(size: 20, weight: .heavy)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
                if let unidad { Text(unidad).font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.apagado) }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.superficie, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Tema.borde, lineWidth: 1))
    }

    @ViewBuilder
    private func pagos(_ c: Cliente) -> some View {
        let lista = c.pagos
        if !lista.isEmpty {
            let hechos = lista.filter { c.estado(de: $0) == .pagado }.count
            tarjeta("Primeros 4 pagos", accesorio: {
                Text("Toca para confirmar").font(Tipo.detalle).foregroundStyle(Tema.apagado)
            }) {
                ZStack(alignment: .top) {
                    GeometryReader { geo in
                        let paso = geo.size.width / 4
                        Capsule().fill(Tema.borde).frame(width: paso * 3, height: 3).offset(x: paso / 2, y: 17)
                        Capsule().fill(Tema.exito).frame(width: paso * CGFloat(max(0, min(3, hechos - 1))), height: 3).offset(x: paso / 2, y: 17)
                    }
                    .frame(height: 40)
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(lista, id: \.num) { pago in
                            let estado = c.estado(de: pago)
                            Button {
                                confirmarCambioPago(c, pago, estado)
                            } label: {
                                VStack(spacing: 6) {
                                    circuloPago(pago, estado)
                                    Text(Fecha.corta(pago.fecha).prefix(5)).font(.system(size: 11)).foregroundStyle(Tema.apagado)
                                    Text(estado.titulo).font(.system(size: 11, weight: .bold)).foregroundStyle(color(estado))
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                let pasados = c.pagosPasadosSinConfirmar
                if !pasados.isEmpty {
                    Button("Confirmar pagos pasados (\(pasados.count))") { store.revisarPagosDe = c.id }
                        .buttonStyle(.pastilla(Tema.acento))
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func circuloPago(_ pago: Pago, _ estado: EstadoPago) -> some View {
        let lado: CGFloat = 36
        switch estado {
        case .pagado, .noPagado:
            Image(systemName: estado == .pagado ? "checkmark" : "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: lado, height: lado)
                .background(Circle().fill(color(estado)).overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))))
                .background(Circle().fill(Tema.superficie).padding(-4))
        case .hoy:
            Text("\(pago.num)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Tema.Seccion.ambar)
                .frame(width: lado, height: lado)
                .background(Circle().fill(Tema.superficie))
                .overlay(Circle().stroke(Tema.advertencia, lineWidth: 2))
                .background(Circle().fill(Tema.superficie).padding(-4))
        case .pendiente:
            Text("\(pago.num)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Tema.apagado)
                .frame(width: lado, height: lado)
                .background(Circle().fill(Tema.superficie2))
                .background(Circle().fill(Tema.superficie).padding(-4))
        }
    }

    // MARK: - Data

    private let columnas = [GridItem(.flexible(), spacing: 14, alignment: .topLeading), GridItem(.flexible(), spacing: 14, alignment: .topLeading)]

    @ViewBuilder
    private func datos(_ c: Cliente) -> some View {
        tarjeta(esCredito(c) || c.categoria == .fraude ? "Crédito" : "Datos", accesorio: {
            if esCredito(c) {
                Menu {
                    ForEach(Estatus.allCases) { e in
                        Button(e.titulo) { confirmarEstatus(c, e) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Estatus: \(c.estatus.titulo)")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tema.acento)
                }
            }
        }) {
            LazyVGrid(columns: columnas, alignment: .leading, spacing: 12) {
                campo("Teléfono", c.tel, mono: true)
                campo("WhatsApp", c.tieneWA ? "Sí" : "No")
                switch c.categoria {
                case .activos?, .sinrenovar?, .fraude?:
                    campo("Asesor", c.asesor)
                    campo("Tipo", c.tipo)
                    campo("Plazo", c.semanas.map { "\($0) semanas" })
                    campo("Día de pago", diaDePago(c))
                    campo("Compra", Fecha.corta(c.fechaCompra))
                    campo("Termina", Fecha.corta(c.fechaFin))
                    if c.categoria == .fraude { campo("Notas", c.notas) }
                case .prospectos?:
                    campo("Origen", c.origen ?? "Manual")
                    campo("Fecha ref.", Fecha.corta(c.fechaRef))
                    campo("Asesor", c.asesor)
                    campo("Verificado", c.verificado ? "Sí" : "No")
                case .prAprobadas?, .prRechazadas?:
                    campo("N° PR", c.numPR, mono: true)
                    campo("Tipo", c.tipocred)
                    campo("Asesor", c.asesor)
                    campo("Solicitud", Fecha.corta(c.fechaSolicitud))
                case nil:
                    EmptyView()
                }
            }
            if let detalles = c.detallesPR, c.categoria?.esPR == true {
                Text(detalles).font(.system(size: 13)).foregroundStyle(Tema.apagado)
            }
            if let curp = c.curp, esCredito(c) || c.categoria == .fraude {
                HStack(spacing: 14) {
                    CodigoQR(texto: curp, lado: 88)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CURP").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(Tema.apagado)
                        Text(curp).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Tema.texto).textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Tema.superficie2.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let titular = store.cliente(c.refDeId) {
                NavigationLink(value: Ruta.cliente(titular.id)) {
                    filaEnlace("Referencia de", titular.nombre)
                }
                .buttonStyle(.plain)
            }
            if let titular = store.cliente(c["clienteSinRenovarId"]?.text) {
                NavigationLink(value: Ruta.cliente(titular.id)) {
                    filaEnlace("Cliente sin renovar", titular.nombre)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Weekly payments fall on the weekday the credit started.
    private func diaDePago(_ c: Cliente) -> String? {
        guard let inicio = c.inicioCredito else { return nil }
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "es_MX")
        formato.dateFormat = "EEEE"
        return formato.string(from: inicio).capitalizedFirst
    }

    private func filaEnlace(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo).font(Tipo.detalle).foregroundStyle(Tema.apagado)
            Spacer()
            Text(valor).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.acento).lineLimit(1)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tema.apagado)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func prAdjunta(_ c: Cliente) -> some View {
        if c.categoria == .sinrenovar, let pr = Reglas.prAdjuntaActiva(c) {
            let aprobada = pr["estatus"]?.text == "aprobada"
            let restantes = Reglas.diasRestantesPRAdjunta(pr)
            tarjeta(aprobada ? "PR aprobada adjunta" : "PR rechazada adjunta", accesorio: {
                Etiqueta("Expira en \(restantes) d", color: aprobada ? Tema.exito : Tema.peligro)
            }) {
                LazyVGrid(columns: columnas, alignment: .leading, spacing: 12) {
                    campo("N° PR", pr["numPR"]?.text, mono: true)
                    campo("Tipo", pr["tipocred"]?.text)
                    campo("Asesor", pr["asesor"]?.text)
                    campo("Solicitud", Fecha.corta(pr["fechaSolicitud"]?.text))
                }
                if let detalles = pr["detallesPR"]?.text, !detalles.isEmpty {
                    Text(detalles).font(.system(size: 13)).foregroundStyle(Tema.apagado)
                }
                Button(role: .destructive) {
                    let tipo = aprobada ? "aprobada" : "rechazada"
                    confirmacion = Confirmacion(
                        titulo: "Eliminar PR adjunta",
                        mensaje: "¿Eliminar la PR \(tipo) \(pr["numPR"]?.text ?? "") de \(c.nombre)? Esto eliminará también el cliente vinculado en la sección de PR \(tipo)s.",
                        boton: "Eliminar", destructivo: true
                    ) { await store.eliminarPRAdjunta(c.id) }
                } label: {
                    Label("Eliminar PR adjunta", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pastilla(Tema.peligro))
            }
        }
    }

    @ViewBuilder
    private func referencias(_ c: Cliente) -> some View {
        let personas: [(String, String, Bool)] = c.categoria == .fraude
            ? store.clientes.filter { $0.refDeId == c.id && $0.categoria == .fraude }.map { ($0.nombre, $0.tel, $0.tieneWA) }
            : c.refs.map { ($0.nombre, $0.tel, c.tieneWA) }
        if !personas.isEmpty {
            tarjeta(c.categoria == .fraude ? "Referencias vinculadas" : "Referencias") {
                VStack(spacing: 0) {
                    ForEach(personas.indices, id: \.self) { i in
                        let persona = personas[i]
                        HStack(spacing: 12) {
                            Text(String(persona.0.split(separator: " ").compactMap(\.first).prefix(2)).uppercased())
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Tema.apagado)
                                .frame(width: 36, height: 36)
                                .background(Tema.superficie2, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(persona.0.isEmpty ? "—" : persona.0).font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.texto).lineLimit(1)
                                Text(persona.1.isEmpty ? "Sin tel." : persona.1).font(.system(size: 12, design: .monospaced)).foregroundStyle(Tema.apagado)
                            }
                            Spacer(minLength: 4)
                            if persona.2, !persona.1.isEmpty, let url = WhatsApp.url(persona.1) {
                                Link(destination: url) {
                                    Image(systemName: "message.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(Tema.Seccion.whatsapp)
                                        .frame(width: 40, height: 40)
                                        .background(Tema.whatsapp.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                }
                                .accessibilityLabel("WhatsApp a \(persona.0)")
                            }
                        }
                        .padding(.vertical, 8)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(Tema.borde.opacity(0.6)).frame(height: 1) }
                        }
                    }
                }
            }
        }
    }

    private func macro(_ c: Cliente) -> some View {
        tarjeta("Macropesos", accesorio: {
            Text(Fecha.actualizacion(c["macropesosFechaActualizacion"]?.text)).font(.system(size: 11)).foregroundStyle(Tema.apagado).lineLimit(1)
        }) {
            HStack(spacing: 8) {
                Text("$").font(.system(size: 18, weight: .bold)).foregroundStyle(Tema.acento)
                TextField("0.00", text: $macropesos)
                    .keyboardType(.decimalPad)
                    .focused($editandoMacro)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Tema.acento)
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
                    .buttonStyle(.pastilla(Tema.acento, relleno: true))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(Tema.acento.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Tema.acento.opacity(0.3), lineWidth: 1))
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
        if let seg = c.seguimiento {
            tarjeta("Seguimiento", accesorio: {
                Etiqueta(seg.tipo, color: Tema.Seccion.morado)
            }) {
                Text(seg.notas.isEmpty ? "Sin notas" : seg.notas).font(.system(size: 14)).foregroundStyle(Tema.texto)
                Text("Desde el \(Fecha.corta(seg.fecha))").font(Tipo.detalle).foregroundStyle(Tema.apagado)
                if store.esAdmin {
                    HStack(spacing: 8) {
                        Button { formulario = .seguimiento(c.id) } label: { Label("Editar", systemImage: "pencil").frame(maxWidth: .infinity) }
                            .buttonStyle(.pastilla(Tema.acento))
                        Button {
                            confirmacion = Confirmacion(titulo: "Quitar seguimiento", mensaje: "¿Quitar el seguimiento de \(c.nombre)?", boton: "Quitar", destructivo: true) {
                                await store.quitarSeguimiento(c.id)
                            }
                        } label: { Label("Quitar", systemImage: "xmark").frame(maxWidth: .infinity) }
                            .buttonStyle(.pastilla(Tema.peligro))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func otroFinanciamiento(_ c: Cliente) -> some View {
        if let otro = store.cliente(c.dobleFinId) {
            let vencido = otro.fechaFin.map { $0 <= Fecha.hoy } ?? false
            let liquidado = (vencido || otro.categoria == .sinrenovar) && otro.estatus != .atraso
            tarjeta("Otro financiamiento", accesorio: {
                if otro.estatus == .atraso {
                    Etiqueta("En atraso", color: Paleta.advertencia)
                } else if liquidado {
                    Etiqueta("Liquidado", color: Tema.acento)
                } else {
                    Etiqueta("Al corriente", color: Paleta.exito)
                }
            }) {
                NavigationLink(value: Ruta.cliente(otro.id)) {
                    HStack(spacing: 12) {
                        IconoCuadro(sistema: "arrow.left.arrow.right", color: Tema.Seccion.morado, lado: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Reglas.esCreditoSecundario(otro, respectoA: c) ? "Crédito anterior" : "Crédito más reciente")
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.texto)
                            Text("\(otro.sl ?? "—") · Vence \(Fecha.corta(otro.fechaFin))")
                                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Tema.apagado)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Tema.apagado)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func acciones(_ c: Cliente) -> some View {
        let liquidacion: Int? = store.esAdmin && c.categoria == .activos ? c.semanasRestantes.flatMap { (0...5).contains($0) ? $0 : nil } : nil
        if !c.historial.isEmpty || liquidacion != nil || store.esAdmin {
            VStack(spacing: 8) {
                if !c.historial.isEmpty {
                    Button { verHistorial = true } label: {
                        Label("Historial: \(c.historial.count) crédito\(c.historial.count == 1 ? "" : "s") anterior\(c.historial.count == 1 ? "" : "es")", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pastilla(Tema.acento))
                }
                if let restantes = liquidacion {
                    Button {
                        confirmacion = Confirmacion(
                            titulo: "⚡ Liquidación anticipada",
                            mensaje: "¿Confirmar la liquidación anticipada de \(c.nombre)? El cliente pasará a \"Sin renovar\" inmediatamente (faltaban \(restantes) semana\(restantes == 1 ? "" : "s")).",
                            boton: "Liquidar"
                        ) { await store.liquidacionAnticipada(c.id) }
                    } label: {
                        Label("Liquidación anticipada (\(restantes) sem.)", systemImage: "bolt.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pastilla(Tema.Seccion.ambar))
                }
                if store.esAdmin, c.categoria == .sinrenovar {
                    Button { Task { await store.alternarSuspension(c.id) } } label: {
                        Label(c.suspendido ? "Reactivar cliente" : "Suspender cliente", systemImage: c.suspendido ? "play.fill" : "pause.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pastilla(Tema.Seccion.ambar))
                }
                if store.esAdmin {
                    Button {
                        let refs = [.activos, .sinrenovar, .fraude].contains(c.categoria) && store.tieneReferenciasVinculadas(c.id)
                        var mensaje = "¿Eliminar \(c.nombre)?"
                        if refs { mensaje += " Sus referencias vinculadas también serán eliminadas." }
                        if c.dobleFinId != nil { mensaje += " El vínculo de doble financiamiento también se eliminará." }
                        confirmacion = Confirmacion(titulo: "Eliminar registro", mensaje: mensaje, boton: "Eliminar", destructivo: true) {
                            await store.eliminar(c.id)
                            dismiss()
                        }
                    } label: {
                        Label("Eliminar registro", systemImage: "trash").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pastilla(Tema.peligro))
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private func color(_ estado: EstadoPago) -> Color {
        switch estado {
        case .pagado: return Tema.Seccion.verde
        case .noPagado: return Tema.Seccion.rojo
        case .hoy: return Tema.Seccion.ambar
        case .pendiente: return Tema.apagado
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
