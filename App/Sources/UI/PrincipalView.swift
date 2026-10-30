import SwiftUI

struct PrincipalView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        TabView {
            NavigationStack { InicioView().conDestinos() }
                .tabItem { Label("Inicio", systemImage: "house.fill") }
            NavigationStack { BaseDatosView().conDestinos() }
                .tabItem { Label("Base de datos", systemImage: "cylinder.split.1x2.fill") }
            NavigationStack { AjustesView() }
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
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

    var body: some View {
        let clientes = store.clientes
        let pagos = Reglas.pagosHoy(clientes)
        let prs = Reglas.prPendientes(clientes)
        let liquidaciones = Reglas.liquidacionesSemana(clientes)
        let seguimiento = Reglas.enSeguimiento(clientes)
        let atrasados = Reglas.atrasados(clientes)

        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saludo).font(.title2.bold())
                    Text(Fecha.larga(Date()).capitalizedFirst).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }

            seccion("Pagos pendientes hoy", icono: "dollarsign.circle.fill", color: Paleta.advertencia, cantidad: pagos.count) {
                ForEach(pagos) { item in
                    FilaPago(cliente: item.cliente, pago: item.pago, atrasado: false, confirmacion: $confirmacion)
                }
            }
            seccion("PR aprobadas pendientes", icono: "checkmark.seal.fill", color: Paleta.exito, cantidad: prs.count) {
                ForEach(prs) { c in
                    NavigationLink(value: Ruta.cliente(c.id)) {
                        FilaSimple(cliente: c, detalle: "\(c.tel.isEmpty ? "Sin tel." : c.tel) · PR: \(c.numPR ?? "—")") {
                            Etiqueta("Aprobada", color: Paleta.exito)
                        }
                    }
                }
            }
            seccion("Liquidaciones esta semana", icono: "banknote.fill", color: .teal, cantidad: liquidaciones.count) {
                ForEach(liquidaciones) { c in
                    NavigationLink(value: Ruta.cliente(c.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            FilaSimple(cliente: c, detalle: "\(c.tel.isEmpty ? "Sin tel." : c.tel) · Vence: \(Fecha.corta(c.fechaFin))") {
                                Text(c.sl ?? "—").font(.caption.monospaced()).foregroundStyle(.tint)
                            }
                            if tieneOtroActivo(c) {
                                Text("⚠️ Tiene otro crédito activo").font(.caption2).foregroundStyle(Paleta.advertencia)
                            }
                        }
                    }
                }
            }
            seccion("Seguimiento a clientes", icono: "list.clipboard.fill", color: Paleta.doble, cantidad: seguimiento.count) {
                ForEach(seguimiento) { c in
                    NavigationLink(value: Ruta.cliente(c.id)) {
                        VStack(alignment: .leading, spacing: 4) {
                            FilaSimple(cliente: c, detalle: "\(c.tel.isEmpty ? "Sin tel." : c.tel) · \(c.seguimiento?.tipo ?? "")") {
                                Etiqueta(c.seguimiento?.tipo ?? "", color: Paleta.advertencia)
                            }
                            if let notas = c.seguimiento?.notas, !notas.isEmpty {
                                Text(notas).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        if store.esAdmin {
                            Button("Quitar seg.", role: .destructive) {
                                confirmacion = Confirmacion(titulo: "Quitar seguimiento", mensaje: "¿Quitar el seguimiento de \(c.nombre)?", boton: "Quitar", destructivo: true) {
                                    await store.quitarSeguimiento(c.id)
                                }
                            }
                        }
                    }
                }
            }
            seccion("Pagos atrasados", icono: "alarm.fill", color: Paleta.peligro, cantidad: atrasados.count, vacio: "Sin pagos atrasados") {
                ForEach(atrasados) { item in
                    FilaPago(cliente: item.cliente, pago: item.pago, atrasado: true, confirmacion: $confirmacion)
                }
            }
        }
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

    private func seccion<Contenido: View>(_ titulo: String, icono: String, color: Color, cantidad: Int, vacio: String = "Sin registros",
                                         @ViewBuilder contenido: () -> Contenido) -> some View {
        Section {
            if cantidad == 0 {
                Text(vacio).foregroundStyle(.secondary)
            } else {
                contenido()
            }
        } header: {
            HStack {
                Label(titulo, systemImage: icono).foregroundStyle(color)
                Spacer()
                Text("\(cantidad)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule())
                    .foregroundStyle(color)
            }
        }
    }
}

/// A payment due today or late, with its actions.
struct FilaPago: View {
    @EnvironmentObject private var store: Store
    let cliente: Cliente
    let pago: Pago
    let atrasado: Bool
    @Binding var confirmacion: Confirmacion?

    var body: some View {
        let arrastre = !atrasado && cliente.pagoHoyConAtraso
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: Ruta.cliente(cliente.id)) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cliente.nombre).font(.headline)
                        HStack(spacing: 8) {
                            Label(cliente.tel.isEmpty ? "Sin tel." : cliente.tel, systemImage: "phone").font(.caption)
                            if let sl = cliente.sl { Text(sl).font(.caption.monospaced()).foregroundStyle(.tint) }
                        }
                        .foregroundStyle(.secondary)
                        if atrasado {
                            Text("Pago \(pago.num) de 4 · \(Fecha.corta(pago.fecha))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Etiqueta("Pago \(pago.num)/4", color: atrasado || arrastre ? Paleta.peligro : Paleta.advertencia)
                }
            }
            if arrastre {
                Text("⚠️ Pago muy atrasado · Este cliente no confirmó el pago anterior")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Paleta.peligro)
            }
            HStack {
                Button {
                    confirmacion = Confirmacion(titulo: "Confirmar pago", mensaje: "¿Confirmar el pago \(pago.num) de 4 de \(cliente.nombre)?", boton: "Confirmar") {
                        await store.confirmarPagos([pago.num], de: cliente.id)
                    }
                } label: {
                    Label("Confirmar pago", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                if atrasado {
                    Button(role: .destructive) {
                        confirmacion = Confirmacion(titulo: "Marcar como no pagado", mensaje: "¿Confirmar que el pago \(pago.num) de 4 de \(cliente.nombre) no fue realizado?", boton: "No pagado", destructivo: true) {
                            await store.marcarNoPagado(pago.num, de: cliente.id)
                        }
                    } label: {
                        Label("No pagado", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
                BotonWhatsApp(cliente: cliente, compacto: true)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}

struct FilaSimple<Accesorio: View>: View {
    let cliente: Cliente
    let detalle: String
    @ViewBuilder let accesorio: () -> Accesorio

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(cliente.nombre).font(.body.weight(.medium))
                Text(detalle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accesorio()
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
