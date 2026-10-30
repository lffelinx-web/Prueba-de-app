import SwiftUI

struct NotificacionesView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmacion: Confirmacion?

    private static let formato: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "d MMM HH:mm"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            List {
                if store.notificacionesVisibles.isEmpty {
                    ContentUnavailableView("Sin notificaciones", systemImage: "tray")
                        .listRowBackground(Color.clear)
                }
                ForEach(store.notificacionesVisibles) { n in
                    fila(n)
                        .swipeActions {
                            Button("Eliminar", role: .destructive) { store.eliminarNotificacion(n.id) }
                        }
                }
            }
            .navigationTitle("Notificaciones")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Borrar todas") {
                        if store.notificacionesVisibles.isEmpty {
                            store.avisar("No hay notificaciones")
                        } else {
                            store.eliminarTodasLasNotificaciones()
                            store.avisar("✓ Notificaciones eliminadas")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
            .confirmacion($confirmacion)
        }
        .capaDeEstado()
    }

    private func fila(_ n: Notificacion) -> some View {
        let cliente = store.cliente(n.clienteId)
        let (icono, titulo): (String, String) = switch n.tipo {
        case "vencido_a_sinrenovar": ("hourglass", "Crédito finalizado")
        case "pr_a_prospecto": ("checkmark.seal", "PR pasó a prospecto")
        default: ("bell", "Notificación")
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icono)
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text(titulo).font(.subheadline.weight(.semibold))
                    Text(n.mensaje).font(.footnote).foregroundStyle(.secondary)
                    Text(NotificacionesView.formato.string(from: Date(timeIntervalSince1970: n.ts / 1000)))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            if n.tipo == "vencido_a_sinrenovar", let cliente, cliente.categoria == .activos, store.esAdmin {
                HStack {
                    Button("Confirmar") {
                        confirmacion = Confirmacion(
                            titulo: "Confirmar fin de crédito",
                            mensaje: "¿Confirmas que el crédito de \(cliente.nombre) ya finalizó? Pasará a Sin renovar.",
                            boton: "Sí, finalizar"
                        ) { await store.confirmarPaseSinRenovar(notificacion: n.id, clienteId: cliente.id) }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Ignorar") { store.eliminarNotificacion(n.id) }
                        .buttonStyle(.bordered)
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AjustesView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var bloqueo: Bloqueo
    @State private var confirmarSalida = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let corta = info?["CFBundleShortVersionString"] as? String ?? "—"
        let compilacion = info?["CFBundleVersion"] as? String ?? "—"
        return "\(corta) (\(compilacion))"
    }

    var body: some View {
        List {
            if let usuario = store.usuario {
                Section {
                    HStack(spacing: 14) {
                        Text(usuario.iniciales)
                            .font(.headline)
                            .frame(width: 46, height: 46)
                            .background(Color.accentColor.opacity(0.2), in: Circle())
                        VStack(alignment: .leading) {
                            Text(usuario.nombre).font(.headline)
                            Text("@\(usuario.username) · \(store.esAdmin ? "Administrador" : "Asesor")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Seguridad") {
                Button {
                    bloqueo.bloquear()
                } label: {
                    Label("Bloquear ahora", systemImage: "lock.fill")
                }
                Button(role: .destructive) {
                    confirmarSalida = true
                } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Section {
                LabeledContent("Versión", value: version)
                LabeledContent("Registros", value: "\(store.clientes.count)")
            } header: {
                Text("Acerca de")
            } footer: {
                Text("Las herramientas de pagos, recordatorios y mensajes de WhatsApp, catálogos, usuarios, asesores, auditoría y exportación a Excel llegarán en las siguientes fases. Mientras tanto siguen disponibles en la versión web.")
            }
        }
        .navigationTitle("Ajustes")
        .conNotificaciones()
        .confirmationDialog("¿Cerrar sesión?", isPresented: $confirmarSalida, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) {
                bloqueo.reiniciar()
                store.cerrarSesion()
            }
        }
    }
}
