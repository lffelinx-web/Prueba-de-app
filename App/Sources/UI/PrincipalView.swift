import SwiftUI

struct PrincipalView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        TabView {
            NavigationStack { InicioView().conDestinos() }
                .tabItem { Label("Inicio", systemImage: "house.fill") }
            NavigationStack { BaseDatosView().conDestinos() }
                .tabItem { Label("Base de datos", systemImage: "cylinder.split.1x2.fill") }
            NavigationStack { HerramientasView().conDestinos() }
                .tabItem { Label("Herramientas", systemImage: "wrench.and.screwdriver.fill") }
        }
    }
}

enum Ruta: Hashable {
    case cliente(String)
    case categoria(Categoria)
}

extension View {
    func conDestinos() -> some View {
        navigationDestination(for: Ruta.self) { ruta in
            switch ruta {
            case .cliente(let id): DetalleView(clienteId: id)
            case .categoria(let categoria): CategoriaView(categoria: categoria)
            }
        }
    }

    /// Bell with the unread count, shown on every main screen.
    func conNotificaciones() -> some View {
        modifier(BotonNotificaciones())
    }
}

private struct BotonNotificaciones: ViewModifier {
    @EnvironmentObject private var store: Store
    @State private var abiertas = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        abiertas = true
                    } label: {
                        let pendientes = store.notificacionesVisibles.filter { !$0.leida }.count
                        Image(systemName: pendientes > 0 ? "bell.badge.fill" : "bell")
                            .overlay(alignment: .topTrailing) {
                                if pendientes > 0 {
                                    Text(pendientes > 99 ? "99+" : "\(pendientes)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .background(Paleta.peligro, in: Capsule())
                                        .offset(x: 10, y: -8)
                                }
                            }
                    }
                    .accessibilityLabel("Notificaciones")
                }
            }
            .sheet(isPresented: $abiertas) {
                NotificacionesView()
            }
    }
}

// MARK: - Inicio

struct InicioView: View {
    @EnvironmentObject private var store: Store
    @State private var confirmacion: Confirmacion?
    @State private var plegadas: Set<String> = []

    var body: some View {
        let clientes = store.clientes
        let pagos = Reglas.pagosHoy(clientes)
        let prs = Reglas.prPendientes(clientes)
        let liquidaciones = Reglas.liquidacionesSemana(clientes)
        let seguimiento = Reglas.enSeguimiento(clientes)
        let atrasados = Reglas.atrasados(clientes)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saludo).font(Tipo.saludo).foregroundStyle(Tema.texto)
                    Text(Fecha.larga(Date()).capitalizedFirst).font(Tipo.dato).foregroundStyle(Tema.apagado)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)

                panel("pagos", "Pagos pendientes hoy", "Vencen hoy", icono: "dollarsign", color: Tema.advertencia, cantidad: pagos.count) {
                    ForEach(pagos) { item in
                        FilaPago(cliente: item.cliente, pago: item.pago, atrasado: false, confirmacion: $confirmacion)
                    }
                }
                panel("atrasados", "Pagos atrasados", "Primeros 4 pagos sin confirmar", icono: "alarm.fill", color: Tema.peligro, cantidad: atrasados.count, vacio: "Sin pagos atrasados") {
                    ForEach(atrasados) { item in
                        FilaPago(cliente: item.cliente, pago: item.pago, atrasado: true, confirmacion: $confirmacion)
                    }
                }
                panel("pr", "PR aprobadas pendientes", "Vigencia de 30 días", icono: "checkmark.seal.fill", color: Tema.exito, cantidad: prs.count) {
                    ForEach(prs) { c in
                        filaCompacta(c, detalle: "PR \(c.numPR ?? "—")") {
                            BotonWhatsApp(cliente: c, compacto: true)
                        }
                    }
                }
                panel("liq", "Liquidaciones esta semana", "De lunes a domingo", icono: "banknote.fill", color: Tema.info, cantidad: liquidaciones.count) {
                    ForEach(liquidaciones) { c in
                        filaCompacta(c, detalle: "Vence \(Fecha.corta(c.fechaFin))", aviso: tieneOtroActivo(c) ? "Tiene otro crédito activo" : nil) {
                            ChipSL(c.sl ?? "—")
                        }
                    }
                }
                panel("seg", "Seguimiento a clientes", "Marcados para seguimiento", icono: "list.clipboard.fill", color: Tema.morado, cantidad: seguimiento.count) {
                    ForEach(seguimiento) { c in
                        filaCompacta(c, detalle: [c.seguimiento?.tipo, c.seguimiento?.notas].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")) {
                            if store.esAdmin {
                                Button {
                                    confirmacion = Confirmacion(titulo: "Quitar seguimiento", mensaje: "¿Quitar el seguimiento de \(c.nombre)?", boton: "Quitar", destructivo: true) {
                                        await store.quitarSeguimiento(c.id)
                                    }
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.pastilla(Tema.peligro))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Tema.fondo)
        .navigationTitle("Centro de datos")
        .navigationBarTitleDisplayMode(.inline)
        .conNotificaciones()
        .confirmacion($confirmacion)
        .overlay {
            if !store.clientesCargados { ProgressView() }
        }
    }

    private var saludo: String {
        let hora = Calendar.current.component(.hour, from: Date())
        let texto = hora < 12 ? "Buenos días" : hora < 18 ? "Buenas tardes" : "Buenas noches"
        return "\(texto), \(store.usuario?.primerNombre ?? "")"
    }

    private func tieneOtroActivo(_ c: Cliente) -> Bool {
        guard let otro = c.dobleFinId else { return false }
        return store.clientes.contains { $0.id == otro && $0.categoria == .activos }
    }

    /// Name and phone on the left, one accessory on the right, a detail line underneath.
    private func filaCompacta<Accesorio: View>(_ c: Cliente, detalle: String, aviso: String? = nil, @ViewBuilder accesorio: () -> Accesorio) -> some View {
        HStack(alignment: .center, spacing: 10) {
            NavigationLink(value: Ruta.cliente(c.id)) {
                VStack(alignment: .leading, spacing: 3) {
                    NombreCliente(nombre: c.nombre)
                    HStack(spacing: 8) {
                        LineaTelefono(tel: c.tel)
                        if !detalle.isEmpty {
                            Text(detalle).font(Tipo.detalle).foregroundStyle(Tema.apagado).lineLimit(1)
                        }
                    }
                    if let aviso {
                        Label(aviso, systemImage: "exclamationmark.triangle.fill").font(Tipo.detalle).foregroundStyle(Tema.advertencia)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            accesorio()
        }
        .padding(.vertical, 10)
    }

    /// One of the web's dashboard cards: its header and its rows inside the same card, foldable.
    private func panel<Contenido: View>(_ clave: String, _ titulo: String, _ subtitulo: String, icono: String, color: Color, cantidad: Int,
                                        vacio: String = "Sin registros", @ViewBuilder contenido: () -> Contenido) -> some View {
        let abierta = !plegadas.contains(clave)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if abierta { plegadas.insert(clave) } else { plegadas.remove(clave) }
                }
            } label: {
                HStack(spacing: 10) {
                    IconoCuadro(sistema: icono, color: color, lado: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(titulo).font(Tipo.encabezado).foregroundStyle(Tema.texto).lineLimit(1)
                        Text(subtitulo).font(Tipo.detalle).foregroundStyle(Tema.apagado).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Etiqueta("\(cantidad)", color: cantidad > 0 ? color : Tema.apagado)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tema.apagado)
                        .rotationEffect(.degrees(abierta ? 0 : -90))
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if abierta {
                Divider().overlay(Tema.borde)
                if cantidad == 0 {
                    Text(vacio)
                        .font(Tipo.dato)
                        .foregroundStyle(Tema.apagado)
                        .padding(12)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        contenido()
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .background(Tema.superficie, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Tema.borde, lineWidth: 1))
    }
}

/// A payment due today or late: who, which payment, and the three actions.
struct FilaPago: View {
    @EnvironmentObject private var store: Store
    let cliente: Cliente
    let pago: Pago
    let atrasado: Bool
    @Binding var confirmacion: Confirmacion?

    var body: some View {
        let arrastre = !atrasado && cliente.pagoHoyConAtraso
        let urgente = atrasado || arrastre
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: Ruta.cliente(cliente.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        NombreCliente(nombre: cliente.nombre)
                        Spacer(minLength: 4)
                        Etiqueta("Pago \(pago.num)/4", color: urgente ? Tema.peligro : Tema.advertencia)
                    }
                    HStack(spacing: 8) {
                        LineaTelefono(tel: cliente.tel)
                        if let sl = cliente.sl { ChipSL(sl) }
                        Spacer(minLength: 0)
                    }
                    if atrasado {
                        Text("Vencía el \(Fecha.corta(pago.fecha))").font(Tipo.detalle).foregroundStyle(Tema.peligro)
                    } else if arrastre {
                        Label("No confirmó el pago anterior", systemImage: "exclamationmark.triangle.fill")
                            .font(Tipo.detalle)
                            .foregroundStyle(Tema.peligro)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    confirmacion = Confirmacion(titulo: "Confirmar pago", mensaje: "¿Confirmar el pago \(pago.num) de 4 de \(cliente.nombre)?", boton: "Confirmar") {
                        await store.confirmarPagos([pago.num], de: cliente.id)
                    }
                } label: {
                    Label("Confirmar", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pastilla(Tema.exito))
                if atrasado {
                    Button {
                        confirmacion = Confirmacion(titulo: "Marcar como no pagado", mensaje: "¿Confirmar que el pago \(pago.num) de 4 de \(cliente.nombre) no fue realizado?", boton: "No pagado", destructivo: true) {
                            await store.marcarNoPagado(pago.num, de: cliente.id)
                        }
                    } label: {
                        Label("No pagó", systemImage: "xmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pastilla(Tema.peligro))
                }
                BotonRecordatorioPago(cliente: cliente, pago: pago, atrasado: urgente)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().overlay(Tema.borde) }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// SL number in the web's blue monospaced chip.
struct ChipSL: View {
    let texto: String

    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto)
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(Tema.acento)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Tema.acento.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Tema.acento.opacity(0.35), lineWidth: 1))
    }
}

/// WhatsApp for a due payment: with the "Pagos de hoy" / "Pagos atrasados" reminder when the user
/// has that template, otherwise just the chat, like the web.
struct BotonRecordatorioPago: View {
    @EnvironmentObject private var store: Store
    let cliente: Cliente
    let pago: Pago
    let atrasado: Bool

    var body: some View {
        let tipo = atrasado ? TipoRecordatorio.pagosAtrasados : .pagosHoy
        if cliente.tieneTelefonoWA, let plantilla = store.plantillaRecordatorio(tipo),
           let url = WhatsApp.url(cliente.tel, mensaje: Mensajes.recordatorio(plantilla, tipo: tipo, cliente: cliente, extras: ExtrasMensaje(numPago: Mensajes.ordinal(pago.num)))) {
            Link(destination: url) {
                Label("Recordar", systemImage: "message.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pastilla(Tema.whatsapp))
        } else if cliente.tieneTelefonoWA, let url = WhatsApp.url(cliente.tel) {
            Link(destination: url) {
                Label("WhatsApp", systemImage: "message.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pastilla(Tema.whatsapp))
        }
    }
}
