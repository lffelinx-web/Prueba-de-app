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
                        .seccionTema()
                        .swipeActions {
                            Button("Eliminar", role: .destructive) { store.eliminarNotificacion(n.id) }
                        }
                }
            }
            .fondoTema()
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
    @AppStorage("temaClaro") private var temaClaro = false
    @AppStorage("faceIDActivo") private var faceIDActivo = false
    @Environment(\.dismiss) private var dismiss
    @State private var confirmarSalida = false
    @State private var pedirContrasena = false
    @State private var contrasena = ""
    @State private var errorContrasena = ""
    @State private var verificando = false
    @State private var excel: URL?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let corta = info?["CFBundleShortVersionString"] as? String ?? "—"
        let compilacion = info?["CFBundleVersion"] as? String ?? "—"
        return "\(corta) (\(compilacion))"
    }

    private struct ArchivoExcel: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    private func exportarExcel() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CentrodeDatos_\(Fecha.hoyISO).xlsx")
        do {
            try Excel.baseDeDatos(store.clientes).write(to: url)
            let activos = store.clientes.filter { $0.categoria == .activos && !$0.inhabilitado }.count
            let sinRenovar = store.clientes.filter { $0.categoria == .sinrenovar && !$0.inhabilitado }.count
            store.avisar("✓ Excel listo (\(activos) activos, \(sinRenovar) sin renovar)")
            excel = url
        } catch {
            store.avisar("No se pudo generar el Excel: \(error.localizedDescription)", advertencia: true)
        }
    }

    private func activarBiometria() async {
        guard let usuario = store.usuario else { return }
        verificando = true
        defer { verificando = false }
        guard await store.verificarContrasena(contrasena) else {
            errorContrasena = "Contraseña incorrecta."
            return
        }
        guard await Biometria.autenticar("Activa \(Biometria.nombre) para Centro de datos", cancelar: "Cancelar") != nil,
              Llavero.guardar(usuario: usuario.username.lowercased(), contrasena: contrasena) else {
            errorContrasena = "No se pudo activar \(Biometria.nombre)."
            return
        }
        faceIDActivo = true
        contrasena = ""
        pedirContrasena = false
        store.avisar("✓ \(Biometria.nombre) activado")
    }

    var body: some View {
        List {
            if let usuario = store.usuario {
                Section {
                    HStack(spacing: 14) {
                        Text(usuario.iniciales)
                            .font(.headline)
                            .foregroundStyle(Tema.acento)
                            .frame(width: 46, height: 46)
                            .background(Tema.acento.opacity(0.15), in: Circle())
                        VStack(alignment: .leading) {
                            Text(usuario.nombre).font(.headline)
                            Text("@\(usuario.username) · \(store.esAdmin ? "Administrador" : "Asesor")")
                                .font(.subheadline).foregroundStyle(Tema.apagado)
                        }
                    }
                }
                .seccionTema()
            }
            if store.esAdmin {
                Section("Administración") {
                    NavigationLink { UsuariosView() } label: { Label("Usuarios", systemImage: "person.badge.key") }
                    NavigationLink { AsesoresView() } label: { Label("Asesores", systemImage: "person.2") }
                    NavigationLink { CatalogosView() } label: { Label("Catálogos", systemImage: "shippingbox") }
                    NavigationLink { DiasBloqueoView() } label: { Label("Días de bloqueo y enviados", systemImage: "calendar.badge.clock") }
                    NavigationLink { AuditoriaView() } label: { Label("Auditoría", systemImage: "list.bullet.rectangle") }
                    Button { exportarExcel() } label: { Label("Exportar base de datos a Excel", systemImage: "tablecells") }
                }
                .seccionTema()
            }
            Section("Cuenta") {
                NavigationLink { CambiarContrasenaView() } label: { Label("Cambiar contraseña", systemImage: "key") }
            }
            .seccionTema()
            Section("Apariencia") {
                Toggle(isOn: $temaClaro) {
                    Label("Tema claro", systemImage: "sun.max")
                }
            }
            .seccionTema()
            Section("Seguridad") {
                if Biometria.disponible {
                    Toggle(isOn: Binding(
                        get: { faceIDActivo },
                        set: { activar in
                            if activar {
                                contrasena = ""
                                errorContrasena = ""
                                pedirContrasena = true
                            } else {
                                Llavero.borrar()
                                faceIDActivo = false
                            }
                        }
                    )) {
                        Label("Usar \(Biometria.nombre)", systemImage: Biometria.icono)
                    }
                }
                Button {
                    dismiss()
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
            .seccionTema()
            Section {
                LabeledContent("Versión", value: version)
                LabeledContent("Registros", value: "\(store.clientes.count)")
            } header: {
                Text("Acerca de")
            } footer: {
                Text("Centro de datos para iPhone. Usa la misma base de datos que la versión web.")
            }
            .seccionTema()
        }
        .fondoTema()
        .navigationTitle("Ajustes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
        }
        .sheet(item: Binding(get: { excel.map(ArchivoExcel.init) }, set: { excel = $0?.url })) { item in
            HojaCompartir(elementos: [item.url])
        }
        .sheet(isPresented: $pedirContrasena) {
            NavigationStack {
                Form {
                    Section {
                        SecureField("Contraseña", text: $contrasena)
                            .textContentType(.password)
                    } footer: {
                        Text("Se guarda cifrada en el llavero de este iPhone y solo se usa después de \(Biometria.nombre).")
                    }
                    .seccionTema()
                    if !errorContrasena.isEmpty {
                        Text(errorContrasena).foregroundStyle(Tema.peligro).seccionTema()
                    }
                }
                .fondoTema()
                .navigationTitle("Confirma tu contraseña")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { pedirContrasena = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Activar") { Task { await activarBiometria() } }
                            .disabled(contrasena.isEmpty || verificando)
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog("¿Cerrar sesión?", isPresented: $confirmarSalida, titleVisibility: .visible) {
            Button("Cerrar sesión", role: .destructive) {
                bloqueo.reiniciar()
                store.cerrarSesion()
            }
        }
    }
}
