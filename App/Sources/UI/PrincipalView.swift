import SwiftUI
import UIKit

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

    /// The web's top bar on the three main tabs: title, user, notifications and settings.
    func conBarraSuperior() -> some View {
        modifier(BarraSuperior())
    }
}

/// Same 38 pt white circle for every top bar button.
private struct CirculoBarra: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: 38, height: 38)
            .background(Tema.superficie, in: Circle())
            .overlay(Circle().stroke(Tema.borde, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

private struct BarraSuperior: ViewModifier {
    @EnvironmentObject private var store: Store
    @State private var notificaciones = false
    @State private var ajustes = false

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: 10) {
                    Text("Centro de datos")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Tema.acento)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 8)
                    Button {
                        notificaciones = true
                    } label: {
                        let pendientes = store.notificacionesVisibles.filter { !$0.leida }.count
                        Image(systemName: pendientes > 0 ? "bell.badge.fill" : "bell.fill")
                            .symbolRenderingMode(.monochrome)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Tema.acento)
                            .modifier(CirculoBarra())
                            .overlay(alignment: .topTrailing) {
                                if pendientes > 0 {
                                    Text(pendientes > 99 ? "99+" : "\(pendientes)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .frame(minWidth: 18, minHeight: 18)
                                        .background(Tema.peligro, in: Capsule())
                                        .overlay(Capsule().stroke(Tema.superficie, lineWidth: 2))
                                        .offset(x: 4, y: -4)
                                }
                            }
                    }
                    .accessibilityLabel("Notificaciones")
                    Button {
                        ajustes = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Tema.acento)
                            .modifier(CirculoBarra())
                    }
                    .accessibilityLabel("Ajustes")
                    if let usuario = store.usuario {
                        Button {
                            ajustes = true
                        } label: {
                            Text(usuario.iniciales.prefix(1))
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(Tema.Seccion.azul).overlay(Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))))
                                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                        }
                        .accessibilityLabel("\(usuario.nombre), \(store.esAdmin ? "administrador" : "asesor")")
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)
                .background(Tema.superficie.ignoresSafeArea(edges: .top))
                .overlay(alignment: .bottom) { Rectangle().fill(Tema.borde).frame(height: 1) }
            }
            .sheet(isPresented: $notificaciones) {
                NotificacionesView()
            }
            .sheet(isPresented: $ajustes) {
                NavigationStack { AjustesView() }
                    .capaDeEstado()
            }
    }
}

// MARK: - Inicio

struct InicioView: View {
    @EnvironmentObject private var store: Store
    @State private var confirmacion: Confirmacion?
    @State private var plegadas: Set<String> = []
    @State private var completas: Set<String> = []

    /// Rows shown before "Ver todos".
    private let filasVisibles = 3

    var body: some View {
        let clientes = store.clientes
        let pagos = Reglas.pagosHoy(clientes)
        let prs = Reglas.prPendientes(clientes)
        let liquidaciones = Reglas.liquidacionesSemana(clientes)
        let seguimiento = Reglas.enSeguimiento(clientes)
        let atrasados = Reglas.atrasados(clientes)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                portada(pagos: pagos.count, atrasados: atrasados.count, liquidaciones: liquidaciones.count)

                panel("pagos", "Pagos pendientes hoy", "Vencen hoy", icono: "dollarsign", color: Tema.Seccion.ambar, cantidad: pagos.count) { limite in
                    ForEach(pagos.prefix(limite)) { item in
                        FilaPago(cliente: item.cliente, pago: item.pago, atrasado: false, confirmacion: $confirmacion)
                    }
                }
                panel("atrasados", "Pagos atrasados", "Primeros 4 pagos sin confirmar", icono: "alarm.fill", color: Tema.Seccion.rojo, cantidad: atrasados.count) { limite in
                    ForEach(atrasados.prefix(limite)) { item in
                        FilaPago(cliente: item.cliente, pago: item.pago, atrasado: true, confirmacion: $confirmacion)
                    }
                }
                panel("pr", "PR aprobadas pendientes", "Vigencia de 30 días", icono: "checkmark.seal.fill", color: Tema.Seccion.verde, cantidad: prs.count) { limite in
                    ForEach(prs.prefix(limite)) { c in
                        filaCompacta(c, detalle: "PR \(c.numPR ?? "—")") {
                            BotonWhatsApp(cliente: c, compacto: true)
                        }
                    }
                }
                panel("liq", "Liquidaciones esta semana", "De lunes a domingo", icono: "banknote.fill", color: Tema.Seccion.cian, cantidad: liquidaciones.count) { limite in
                    ForEach(liquidaciones.prefix(limite)) { c in
                        filaCompacta(c, detalle: "Vence \(Fecha.corta(c.fechaFin))", aviso: tieneOtroActivo(c) ? "Tiene otro crédito activo" : nil) {
                            ChipSL(c.sl ?? "—")
                        }
                    }
                }
                panel("seg", "Seguimiento a clientes", "Marcados para seguimiento", icono: "list.clipboard.fill", color: Tema.Seccion.morado, cantidad: seguimiento.count) { limite in
                    ForEach(seguimiento.prefix(limite)) { c in
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
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .background(Tema.fondo)
        .conBarraSuperior()
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

    private func plural(_ n: Int, _ singular: String, _ plural: String) -> String {
        "\(n) \(n == 1 ? singular : plural)"
    }

    /// Greeting on the blue gradient, with a one-line summary of the day.
    private func portada(pagos: Int, atrasados: Int, liquidaciones: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(saludo)
                    .font(.system(size: 24, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(Fecha.larga(Date()).capitalizedFirst)
                    .font(.system(size: 14))
                    .opacity(0.82)
            }
            Rectangle().fill(.white.opacity(0.2)).frame(height: 1)
            (Text("Hoy tienes ")
                + Text(plural(pagos, "pago pendiente", "pagos pendientes")).bold()
                + Text(", ")
                + Text(plural(atrasados, "atrasado", "atrasados")).bold()
                + Text(" y ")
                + Text(plural(liquidaciones, "liquidación", "liquidaciones")).bold()
                + Text(" esta semana."))
                .font(.system(size: 13))
                .opacity(0.94)
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tema.degradadoPortada, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: 0x0f3a73).opacity(0.35), radius: 14, x: 0, y: 10)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .top) { Rectangle().fill(Tema.borde.opacity(0.6)).frame(height: 1) }
    }

    /// A section card: tinted header with its gradient icon and count, rows inside, foldable.
    /// Empty sections collapse to one line.
    private func panel<Contenido: View>(_ clave: String, _ titulo: String, _ subtitulo: String, icono: String, color: Color, cantidad: Int,
                                        @ViewBuilder contenido: (Int) -> Contenido) -> some View {
        let abierta = cantidad > 0 && !plegadas.contains(clave)
        let todas = completas.contains(clave)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                guard cantidad > 0 else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    if plegadas.contains(clave) { plegadas.remove(clave) } else { plegadas.insert(clave) }
                }
            } label: {
                HStack(spacing: 12) {
                    IconoCuadro(sistema: icono, color: color, lado: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(titulo).font(Tipo.encabezado).foregroundStyle(cantidad > 0 ? color : Tema.texto).lineLimit(1)
                        Text(subtitulo).font(Tipo.detalle).foregroundStyle(Tema.apagado).lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    if cantidad > 0 {
                        Etiqueta("\(cantidad)", color: color)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Tema.apagado)
                            .rotationEffect(.degrees(abierta ? 0 : -90))
                    } else {
                        Text("Sin pendientes").font(Tipo.detalle.weight(.semibold)).foregroundStyle(Tema.apagado)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(cantidad > 0 ? LinearGradient(colors: [color.opacity(0.14), color.opacity(0.05)], startPoint: .top, endPoint: .bottom) : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if abierta {
                contenido(todas ? cantidad : filasVisibles)
                if cantidad > filasVisibles {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if todas { completas.remove(clave) } else { completas.insert(clave) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(todas ? "Mostrar menos" : "Ver todos (\(cantidad))")
                            Image(systemName: todas ? "chevron.up" : "chevron.right")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tema.acento)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(alignment: .top) { Rectangle().fill(Tema.borde.opacity(0.6)).frame(height: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Tema.superficie, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(abierta ? color.opacity(0.3) : Tema.borde, lineWidth: 1))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Tema.borde.opacity(0.6)).frame(height: 1) }
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

/// Folio chip that copies itself when tapped.
struct ChipCopiable: View {
    @EnvironmentObject private var store: Store
    let texto: String
    var etiqueta = "SL"

    var body: some View {
        Button {
            UIPasteboard.general.string = texto
            store.avisar("✓ \(etiqueta) copiado")
        } label: {
            HStack(spacing: 4) {
                Text(texto).font(.system(size: 11, weight: .bold, design: .monospaced)).lineLimit(1).fixedSize()
                Image(systemName: "doc.on.doc").font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(Tema.acento)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Tema.acento.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Tema.acento.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copiar \(etiqueta) \(texto)")
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
            .buttonStyle(.pastilla(Tema.Seccion.whatsapp, relleno: true))
        } else if cliente.tieneTelefonoWA, let url = WhatsApp.url(cliente.tel) {
            Link(destination: url) {
                Label("WhatsApp", systemImage: "message.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.pastilla(Tema.Seccion.whatsapp, relleno: true))
        }
    }
}
