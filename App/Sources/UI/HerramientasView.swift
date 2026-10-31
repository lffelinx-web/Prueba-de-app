import SwiftUI
import UIKit

enum RutaHerramienta: Hashable {
    case pagos
    case recordatorios
    case macropesos
    case recordatorio(TipoRecordatorio)
    case mensajes(masivos: Bool)
    case subtiposSinRenovar
    case envio(masivos: Bool, categoria: CategoriaMensaje, cuerpo: CuerpoMensaje?)
    case ajustes
    case plantillas
}

/// The web's "Herramientas" tab: payments by day, WhatsApp reminders and messages.
struct HerramientasView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                botonGrande(.pagos, "Ver pagos", "Ayer, hoy y mañana", icono: "calendar", color: Tema.acento)
                botonGrande(.recordatorios, "Recordatorios", "Macropesos y crédito disponible por WhatsApp", icono: "iphone.radiowaves.left.and.right", color: Tema.whatsapp)
                botonGrande(.mensajes(masivos: true), "Mensajes masivos", "Mismo mensaje para muchos contactos", icono: "megaphone.fill", color: Tema.advertencia)
                botonGrande(.mensajes(masivos: false), "Mensajes personalizados", "Mensaje individualizado por contacto", icono: "envelope.fill", color: Tema.morado)
            }
            .padding()
        }
        .background(Tema.fondo)
        .navigationTitle("Herramientas")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: RutaHerramienta.ajustes) {
                    Label("Configuración", systemImage: "gearshape")
                }
            }
        }
        .conNotificaciones()
        .navigationDestination(for: RutaHerramienta.self) { ruta in
            switch ruta {
            case .pagos: VerPagosView()
            case .recordatorios: MenuRecordatoriosView()
            case .macropesos: MenuMacropesosView()
            case .recordatorio(let tipo): ListaRecordatorioView(tipo: tipo)
            case .mensajes(let masivos): MenuMensajesView(masivos: masivos)
            case .subtiposSinRenovar: MenuSubtiposSinRenovarView()
            case .envio(let masivos, let categoria, let cuerpo): ListaEnvioView(masivos: masivos, categoria: categoria, cuerpo: cuerpo)
            case .ajustes: AjustesView()
            case .plantillas: PlantillasView()
            }
        }
    }

    private func botonGrande(_ ruta: RutaHerramienta, _ titulo: String, _ detalle: String, icono: String, color: Color) -> some View {
        NavigationLink(value: ruta) {
            OpcionMenu(titulo: titulo, detalle: detalle, icono: icono, color: color)
        }
        .buttonStyle(.plain)
    }
}

/// A row-shaped menu button, like the web's `.btn-detail` menu entries.
struct OpcionMenu: View {
    let titulo: String
    let detalle: String
    let icono: String
    var color: Color = Tema.acento

    var body: some View {
        HStack(spacing: 12) {
            IconoCuadro(sistema: icono, color: color, lado: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.subheadline.weight(.semibold)).foregroundStyle(Tema.texto)
                Text(detalle).font(.caption).foregroundStyle(Tema.apagado).lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Tema.apagado)
        }
        .tarjeta()
        .contentShape(Rectangle())
    }
}

// MARK: - Ver pagos

struct VerPagosView: View {
    @EnvironmentObject private var store: Store
    @State private var dia = 0

    var body: some View {
        let pagos = Envios.pagos(enDia: dia, de: store.clientes)
        List {
            Section {
                Picker("Día", selection: $dia) {
                    Text("Ayer (\(Envios.pagos(enDia: -1, de: store.clientes).count))").tag(-1)
                    Text("Hoy (\(Envios.pagos(enDia: 0, de: store.clientes).count))").tag(0)
                    Text("Mañana (\(Envios.pagos(enDia: 1, de: store.clientes).count))").tag(1)
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))

            if pagos.isEmpty {
                Text("Sin pagos para \(dia == -1 ? "ayer" : dia == 0 ? "hoy" : "mañana")")
                    .foregroundStyle(Tema.apagado)
                    .frame(maxWidth: .infinity)
                    .filaTarjeta()
            }
            ForEach(pagos) { item in
                let c = item.cliente
                NavigationLink(value: Ruta.cliente(c.id)) {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(c.nombre).font(.headline).lineLimit(1)
                            Spacer()
                            Etiqueta("P\(item.numero)/\(item.total)", color: Tema.advertencia)
                        }
                        HStack(spacing: 6) {
                            Label(c.tel.isEmpty ? "—" : c.tel, systemImage: "phone").font(.caption).foregroundStyle(Tema.texto)
                            ChipSL(c.sl ?? "—")
                        }
                        HStack {
                            Text("💰 \(Dinero.texto(c.macropesos))")
                                .font(.subheadline.monospaced().weight(.semibold))
                                .foregroundStyle(c.macropesos == nil ? Tema.apagado : Tema.acento)
                            Spacer()
                            BotonWhatsApp(cliente: c, compacto: true)
                        }
                        ProgressView(value: Double(item.porcentaje), total: 100)
                            .tint(Tema.acento)
                        Text("\(item.porcentaje)%").font(.caption).foregroundStyle(Tema.apagado).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .tarjeta()
                }
                .filaTarjeta()
            }
        }
        .listStyle(.plain)
        .fondoTema()
        .navigationTitle("Ver pagos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Reminders

struct MenuRecordatoriosView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                NavigationLink(value: RutaHerramienta.macropesos) {
                    OpcionMenu(titulo: "Macropesos", detalle: "Disponibles e invitación a ganar más", icono: "banknote", color: Tema.acento)
                }
                NavigationLink(value: RutaHerramienta.recordatorio(.creditoDisponible)) {
                    OpcionMenu(titulo: "Crédito disponible", detalle: "Clientes con crédito disponible para renovar", icono: "chart.bar.fill", color: Tema.exito)
                }
            }
            .buttonStyle(.plain)
            .padding()
        }
        .background(Tema.fondo)
        .navigationTitle("Envío de recordatorio")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MenuMacropesosView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                NavigationLink(value: RutaHerramienta.recordatorio(.macropesosDisponibles)) {
                    OpcionMenu(titulo: TipoRecordatorio.macropesosDisponibles.titulo, detalle: TipoRecordatorio.macropesosDisponibles.descripcion, icono: "banknote", color: Tema.acento)
                }
                NavigationLink(value: RutaHerramienta.recordatorio(.macropesosInvitacion)) {
                    OpcionMenu(titulo: TipoRecordatorio.macropesosInvitacion.titulo, detalle: TipoRecordatorio.macropesosInvitacion.descripcion, icono: "gift.fill", color: Tema.morado)
                }
            }
            .buttonStyle(.plain)
            .padding()
        }
        .background(Tema.fondo)
        .navigationTitle("Macropesos")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Clients for one reminder type, each with WhatsApp, "marcar enviado" and its extra field.
struct ListaRecordatorioView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openURL) private var openURL
    let tipo: TipoRecordatorio

    @State private var macroMinimo = ""
    @State private var lineas: [String: String] = [:]
    @State private var accesorios: [String: String] = [:]
    @State private var confirmacion: Confirmacion?
    @State private var verBloqueados = false
    @State private var qr: Cliente?

    var body: some View {
        let candidatos = Envios.candidatosRecordatorio(tipo, en: store.clientes, macroMinimo: Double(macroMinimo) ?? 0)
        let bloqueados = candidatos.filter { Envios.recordatorioBloqueado($0, dias: store.diasBloqueo) }
        let lista = candidatos.filter { !Envios.recordatorioBloqueado($0, dias: store.diasBloqueo) }
        let plantilla = store.plantillaRecordatorio(tipo)
        let conAccesorio = tipo == .macropesosDisponibles && plantilla?.avanzadasActivas == true

        List {
            Section {
                HStack {
                    Text(lista.isEmpty ? "Sin clientes disponibles" : "\(lista.count) cliente\(lista.count == 1 ? "" : "s") disponible\(lista.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(Tema.apagado)
                    Spacer()
                    if !bloqueados.isEmpty {
                        Button("🔒 \(bloqueados.count) bloqueado\(bloqueados.count == 1 ? "" : "s")") { verBloqueados = true }
                            .buttonStyle(.pastilla())
                    }
                }
                if plantilla == nil {
                    Label("Configura primero la plantilla en Configuración → Plantillas.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Tema.advertencia)
                }
                if tipo == .macropesosDisponibles {
                    HStack {
                        Text("Mín. macropesos").font(.subheadline).foregroundStyle(Tema.apagado)
                        TextField("$0", text: $macroMinimo)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if conAccesorio, store.accesoriosConPrecio.isEmpty {
                        Text("⚠️ No hay accesorios con precio en el catálogo.").font(.caption).foregroundStyle(Tema.advertencia)
                    }
                }
            }
            .seccionTema()

            ForEach(lista) { c in
                fila(c, plantilla: plantilla, conAccesorio: conAccesorio)
                    .tarjeta()
                    .filaTarjeta()
            }
        }
        .listStyle(.plain)
        .fondoTema()
        .navigationTitle(tipo.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .confirmacion($confirmacion)
        .sheet(isPresented: $verBloqueados) {
            BloqueadosRecordatorioView(clientes: bloqueados)
        }
        .sheet(item: $qr) { c in
            NavigationStack {
                VStack(spacing: 14) {
                    if let curp = c.curp {
                        CodigoQR(texto: curp)
                        Text(curp).font(.callout.monospaced())
                    } else {
                        ContentUnavailableView("Sin CURP registrada", systemImage: "qrcode")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Tema.fondo)
                .navigationTitle(c.nombre)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func fila(_ c: Cliente, plantilla: PlantillaRecordatorio?, conAccesorio: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.nombre).font(.subheadline.weight(.semibold)).lineLimit(1)
                    switch tipo {
                    case .macropesosDisponibles:
                        Text("💰 \(Dinero.texto(c.macropesos ?? 0)) · \(c.sl ?? "—")").font(.caption.monospaced()).foregroundStyle(Tema.acento)
                    case .creditoDisponible:
                        Text("\(c.sl ?? "—") · \(c.semanasRestantes ?? 0) sem.").font(.caption.monospaced()).foregroundStyle(Tema.acento)
                    default:
                        Text(c.sl ?? "—").font(.caption.monospaced()).foregroundStyle(Tema.apagado)
                    }
                }
                Spacer()
                Button {
                    enviar(c, plantilla: plantilla, conAccesorio: conAccesorio)
                } label: {
                    Image(systemName: "message.fill")
                }
                .buttonStyle(.pastilla(Tema.whatsapp, relleno: true))
                if tipo == .macropesosDisponibles {
                    Button { qr = c } label: { Image(systemName: "qrcode") }
                        .buttonStyle(.pastilla())
                }
                Button {
                    confirmacion = Confirmacion(
                        titulo: "Marcar como enviado",
                        mensaje: "¿Marcar a \(c.nombre) como enviado? Quedará bloqueado \(store.diasBloqueo.dias("activos")) días para esta categoría.",
                        boton: "Marcar"
                    ) {
                        if await store.marcarRecordatorioEnviado([c.id]) { store.avisar("✓ Marcado como enviado") }
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.pastilla())
            }
            if tipo == .creditoDisponible {
                TextField("Línea de crédito $", text: Binding(get: { lineas[c.id] ?? "" }, set: { lineas[c.id] = $0 }))
                    .keyboardType(.decimalPad)
                    .campoTema()
            }
            if conAccesorio, !store.accesoriosConPrecio.isEmpty {
                Picker("Accesorio", selection: Binding(get: { accesorios[c.id] ?? "" }, set: { accesorios[c.id] = $0 })) {
                    Text("— Seleccionar accesorio —").tag("")
                    ForEach(store.accesoriosConPrecio, id: \.nombre) { a in
                        Text("\(a.nombre) — \(Dinero.texto(a.precio))").tag(a.nombre)
                    }
                }
                .font(.caption)
                if let elegido = store.accesoriosConPrecio.first(where: { $0.nombre == accesorios[c.id] }) {
                    let resto = max(0, elegido.precio - (c.macropesos ?? 0))
                    Text(resto > 0 ? "Diferencia: \(Dinero.texto(resto))" : "✓ Cubierto totalmente por sus macropesos")
                        .font(.caption.monospaced())
                        .foregroundStyle(resto > 0 ? Tema.advertencia : Tema.acento)
                }
            }
        }
    }

    private func enviar(_ c: Cliente, plantilla: PlantillaRecordatorio?, conAccesorio: Bool) {
        guard !c.tel.isEmpty else { return store.avisar("Cliente sin teléfono", advertencia: true) }
        guard c.tieneWA else { return store.avisar("Cliente sin WhatsApp", advertencia: true) }
        guard let plantilla else { return store.avisar("Configura primero la plantilla en Configuración", advertencia: true) }
        var extras = ExtrasMensaje()
        if tipo == .creditoDisponible {
            let linea = (lineas[c.id] ?? "").trimmingCharacters(in: .whitespaces)
            guard let monto = Double(linea), monto > 0 else { return store.avisar("Captura la línea de crédito", advertencia: true) }
            extras.lineaCredito = String(monto)
        }
        if conAccesorio {
            guard let elegido = store.accesoriosConPrecio.first(where: { $0.nombre == accesorios[c.id] }) else {
                return store.avisar("Selecciona un accesorio", advertencia: true)
            }
            extras.accesorioNombre = elegido.nombre
            extras.accesorioPrecio = elegido.precio
        }
        let mensaje = Mensajes.recordatorio(plantilla, tipo: tipo, cliente: c, extras: extras)
        if let url = WhatsApp.url(c.tel, mensaje: mensaje) { openURL(url) }
    }
}

struct BloqueadosRecordatorioView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let clientes: [Cliente]
    @State private var confirmacion: Confirmacion?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(clientes) { c in
                        let ultimo = Envios.ultimoRecordatorio(c)
                        let dias = Int((Envios.ahora() - ultimo) / Envios.dia)
                        let restantes = max(0, store.diasBloqueo.dias("activos") - dias)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.nombre).font(.subheadline.weight(.medium))
                                Text("⏱ Hace \(dias) día\(dias == 1 ? "" : "s") · \(restantes) día\(restantes == 1 ? "" : "s") restante\(restantes == 1 ? "" : "s")")
                                    .font(.caption.monospaced()).foregroundStyle(Tema.apagado)
                            }
                            Spacer()
                            if store.esAdmin {
                                Button {
                                    Task { if await store.desbloquearRecordatorio([c.id]) { store.avisar("✓ Cliente desbloqueado") } }
                                } label: {
                                    Image(systemName: "lock.open")
                                }
                                .buttonStyle(.pastilla(Tema.acento))
                            }
                        }
                    }
                } header: {
                    Text("Estos clientes recibieron mensaje en los últimos \(store.diasBloqueo.dias("activos")) días.").textCase(nil)
                }
                .seccionTema()
                if store.esAdmin, clientes.count > 1 {
                    Button("Desbloquear todos (\(clientes.count))", role: .destructive) {
                        confirmacion = Confirmacion(titulo: "Desbloquear todos", mensaje: "¿Desbloquear a todos los clientes bloqueados en esta categoría?", boton: "Desbloquear todos") {
                            if await store.desbloquearRecordatorio(clientes.map(\.id)) { dismiss() }
                        }
                    }
                    .seccionTema()
                }
            }
            .fondoTema()
            .navigationTitle("Bloqueados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .confirmacion($confirmacion)
        }
        .capaDeEstado()
    }
}

extension View {
    /// Text field on the web's darker surface, for inputs inside cards.
    func campoTema() -> some View {
        font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Tema.superficie2, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Tema.borde, lineWidth: 1))
    }
}

/// System share sheet for an exported file.
struct HojaCompartir: UIViewControllerRepresentable {
    let elementos: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: elementos, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
