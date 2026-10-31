import SwiftUI

// MARK: - Users

struct UsuariosView: View {
    @EnvironmentObject private var store: Store
    @State private var editando: UsuarioEditado?
    @State private var confirmacion: Confirmacion?

    struct UsuarioEditado: Identifiable {
        let id: String
        let usuario: Usuario?
    }

    var body: some View {
        List {
            Section {
                ForEach(store.usuarios.sorted { $0.nombre.localizedCompare($1.nombre) == .orderedAscending }) { u in
                    HStack(spacing: 12) {
                        Text(u.iniciales)
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(u.rol == "admin" ? Tema.Seccion.azul : Tema.Seccion.verde))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(u.nombre).font(.system(size: 15, weight: .semibold))
                            Text("@\(u.username)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Tema.apagado)
                        }
                        Spacer()
                        Etiqueta(u.rol == "admin" ? "Admin" : "Asesor", color: u.rol == "admin" ? Tema.acento : Tema.exito)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editando = UsuarioEditado(id: u.id, usuario: u) }
                    .swipeActions {
                        if u.id != store.usuario?.id {
                            Button("Desactivar", role: .destructive) {
                                confirmacion = Confirmacion(titulo: "Desactivar usuario", mensaje: "¿Revocar el acceso de \(u.nombre)?", boton: "Desactivar", destructivo: true) {
                                    do {
                                        try await store.desactivarUsuario(u.id)
                                        store.avisar("✓ Usuario desactivado")
                                    } catch {
                                        store.avisar(error.localizedDescription, advertencia: true)
                                    }
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("Toca un usuario para editar su nombre o rol. Desliza para revocar su acceso.")
            }
            .seccionTema()
        }
        .fondoTema()
        .navigationTitle("Usuarios")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editando = UsuarioEditado(id: "nuevo", usuario: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuevo usuario")
            }
        }
        .sheet(item: $editando) { item in
            FormularioUsuario(usuario: item.usuario).capaDeEstado()
        }
        .confirmacion($confirmacion)
    }
}

private struct FormularioUsuario: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let usuario: Usuario?

    @State private var nombre = ""
    @State private var username = ""
    @State private var rol = "usuario"
    @State private var contrasena = ""
    @State private var error = ""
    @State private var guardando = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre completo", text: $nombre)
                    TextField("Usuario (sin espacios)", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(usuario != nil)
                    Picker("Rol", selection: $rol) {
                        Text("Asesor").tag("usuario")
                        Text("Administrador").tag("admin")
                    }
                }
                .seccionTema()
                if usuario == nil {
                    Section {
                        SecureField("Contraseña (mínimo 12 caracteres)", text: $contrasena)
                    } footer: {
                        Text("Cada usuario podrá cambiar su contraseña desde su cuenta.")
                    }
                    .seccionTema()
                }
                if !error.isEmpty {
                    Text(error).foregroundStyle(Tema.peligro).seccionTema()
                }
            }
            .fondoTema()
            .navigationTitle(usuario == nil ? "Nuevo usuario" : "Editar usuario")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await guardar() } }.bold().disabled(guardando)
                }
            }
            .onAppear {
                if let usuario {
                    nombre = usuario.nombre
                    username = usuario.username
                    rol = usuario.rol == "admin" ? "admin" : "usuario"
                }
            }
        }
    }

    private func guardar() async {
        guardando = true
        defer { guardando = false }
        do {
            if let usuario {
                try await store.editarUsuario(usuario.id, nombre: nombre, rol: rol)
                store.avisar("✓ Usuario actualizado")
            } else {
                try await store.crearUsuario(nombre: nombre, username: username, rol: rol, contrasena: contrasena)
                store.avisar("✓ Usuario creado")
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Advisors

struct AsesoresView: View {
    @EnvironmentObject private var store: Store
    @State private var editando: AsesorEditado?
    @State private var confirmacion: Confirmacion?

    struct AsesorEditado: Identifiable {
        let id: String
        let original: String?
    }

    var body: some View {
        List {
            Section {
                if store.asesores.isEmpty {
                    Text("No hay asesores. Agrega uno con +.").foregroundStyle(Tema.apagado)
                }
                ForEach(store.asesores, id: \.self) { nombre in
                    HStack(spacing: 12) {
                        Text(String(nombre.split(separator: " ").compactMap(\.first).prefix(2)).uppercased())
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Tema.Seccion.verde))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nombre).font(.system(size: 15, weight: .semibold))
                            let usos = store.clientes.filter { $0.asesor == nombre }.count
                            Text("\(usos) cliente\(usos == 1 ? "" : "s")").font(Tipo.detalle).foregroundStyle(Tema.apagado)
                        }
                        Spacer()
                        Toggle("Disponible en altas", isOn: Binding(
                            get: { store.asesorDisponible(nombre) },
                            set: { valor in
                                Task {
                                    do { try await store.cambiarDisponibilidad(nombre, disponible: valor) } catch { store.avisar(error.localizedDescription, advertencia: true) }
                                }
                            }
                        ))
                        .labelsHidden()
                        .disabled(!store.visibilidadCargada)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editando = AsesorEditado(id: nombre, original: nombre) }
                    .swipeActions {
                        Button("Eliminar", role: .destructive) {
                            let usos = store.clientes.filter { $0.asesor == nombre }.count
                            let aviso = usos > 0 ? " \(usos) cliente\(usos == 1 ? "" : "s") lo tiene\(usos == 1 ? "" : "n") asignado; conservarán el nombre, pero ya no estará disponible para nuevos." : ""
                            confirmacion = Confirmacion(titulo: "Eliminar asesor", mensaje: "¿Eliminar al asesor \(nombre)?" + aviso, boton: "Eliminar", destructivo: true) {
                                do {
                                    try await store.eliminarAsesor(nombre)
                                    store.avisar("Asesor eliminado")
                                } catch {
                                    store.avisar(error.localizedDescription, advertencia: true)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text("El interruptor indica si el asesor aparece al dar de alta clientes nuevos.")
            }
            .seccionTema()
        }
        .fondoTema()
        .navigationTitle("Asesores")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editando = AsesorEditado(id: "nuevo", original: nil) } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Nuevo asesor")
            }
        }
        .sheet(item: $editando) { item in
            FormularioNombre(titulo: item.original == nil ? "Nuevo asesor" : "Editar asesor", etiqueta: "Nombre del asesor", inicial: item.original ?? "") { nombre in
                try await store.guardarAsesor(nombre: nombre, original: item.original)
                store.avisar(item.original == nil ? "✓ Asesor agregado" : "✓ Asesor actualizado")
            }
            .capaDeEstado()
        }
        .confirmacion($confirmacion)
    }
}

/// A one-field form used for advisors, brands and models.
private struct FormularioNombre: View {
    @Environment(\.dismiss) private var dismiss
    let titulo: String
    let etiqueta: String
    let inicial: String
    var conPrecio = false
    var precioInicial = ""
    let guardar: (String) async throws -> Void
    var guardarConPrecio: ((String, Double) async throws -> Void)?

    @State private var texto = ""
    @State private var precio = ""
    @State private var error = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(etiqueta, text: $texto)
                    if conPrecio {
                        TextField("Precio (MXN)", text: $precio).keyboardType(.decimalPad)
                    }
                }
                .seccionTema()
                if !error.isEmpty { Text(error).foregroundStyle(Tema.peligro).seccionTema() }
            }
            .fondoTema()
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        Task {
                            do {
                                let limpio = Texto.limpio(texto)
                                if conPrecio {
                                    guard let valor = Double(precio.replacingOccurrences(of: ",", with: "")), valor >= 0 else {
                                        error = "Captura un precio válido."
                                        return
                                    }
                                    try await guardarConPrecio?(limpio, valor)
                                } else {
                                    try await guardar(limpio)
                                }
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .bold()
                }
            }
            .onAppear {
                texto = inicial
                precio = precioInicial
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Catalogues

struct CatalogosView: View {
    @EnvironmentObject private var store: Store
    @State private var nuevaMarca = false
    @State private var confirmacion: Confirmacion?

    private static let iconos = ["iPhone": "iphone", "Pantallas": "tv", "Bicis": "bicycle", "Motos": "scooter", "Accesorios": "headphones"]

    var body: some View {
        List {
            Section {
                ForEach(Store.categoriasProducto, id: \.self) { categoria in
                    NavigationLink {
                        ModelosProductoView(categoria: categoria)
                    } label: {
                        HStack(spacing: 12) {
                            IconoCuadro(sistema: CatalogosView.iconos[categoria] ?? "shippingbox", color: Tema.Seccion.azul, lado: 32)
                            Text(categoria).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("\(store.catalogoProductos[categoria]?.count ?? 0)").foregroundStyle(Tema.apagado)
                        }
                    }
                }
            } header: {
                Text("Productos")
            } footer: {
                Text("Se usan en los mensajes de PR (tipo de producto y modelo). Los accesorios llevan precio para el recordatorio de macropesos.")
            }
            .seccionTema()

            Section {
                let marcas = store.catalogoCelulares.keys.sorted()
                if marcas.isEmpty { Text("Sin marcas registradas").foregroundStyle(Tema.apagado) }
                ForEach(marcas, id: \.self) { marca in
                    NavigationLink {
                        ModelosCelularView(marca: marca)
                    } label: {
                        HStack(spacing: 12) {
                            IconoCuadro(sistema: "iphone.gen3", color: Tema.Seccion.morado, lado: 32)
                            Text(marca).font(.system(size: 15, weight: .semibold))
                            Spacer()
                            Text("\(store.catalogoCelulares[marca]?.count ?? 0)").foregroundStyle(Tema.apagado)
                        }
                    }
                    .swipeActions {
                        Button("Eliminar", role: .destructive) {
                            confirmacion = Confirmacion(titulo: "Eliminar marca", mensaje: "¿Eliminar \(marca) y todos sus modelos?", boton: "Eliminar", destructivo: true) {
                                do { try await store.eliminarMarca(marca); store.avisar("✓ Marca eliminada") } catch { store.avisar("Error al eliminar", advertencia: true) }
                            }
                        }
                    }
                }
                Button { nuevaMarca = true } label: { Label("Agregar marca", systemImage: "plus") }
            } header: {
                Text("Celulares")
            } footer: {
                Text("Se usan como equipo en los mensajes de Financing.")
            }
            .seccionTema()
        }
        .fondoTema()
        .navigationTitle("Catálogos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $nuevaMarca) {
            FormularioNombre(titulo: "Nueva marca", etiqueta: "Marca", inicial: "") { marca in
                guard !marca.isEmpty else { throw ErrorAdmin("Escribe una marca.") }
                guard store.catalogoCelulares[marca] == nil else { throw ErrorAdmin("Esa marca ya existe.") }
                try await store.guardarModelosCelular(marca: marca, modelos: [])
                store.avisar("✓ Marca agregada")
            }
            .capaDeEstado()
        }
        .confirmacion($confirmacion)
    }
}

private struct ModelosCelularView: View {
    @EnvironmentObject private var store: Store
    let marca: String
    @State private var nuevo = false

    var body: some View {
        let modelos = store.catalogoCelulares[marca] ?? []
        List {
            Section {
                if modelos.isEmpty { Text("Sin modelos").foregroundStyle(Tema.apagado) }
                ForEach(modelos.indices, id: \.self) { i in
                    Text(modelos[i])
                        .swipeActions {
                            Button("Eliminar", role: .destructive) {
                                var lista = modelos
                                lista.remove(at: i)
                                Task { try? await store.guardarModelosCelular(marca: marca, modelos: lista) }
                            }
                        }
                }
                Button { nuevo = true } label: { Label("Agregar modelo", systemImage: "plus") }
            }
            .seccionTema()
        }
        .fondoTema()
        .navigationTitle(marca)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $nuevo) {
            FormularioNombre(titulo: "Nuevo modelo", etiqueta: "Modelo", inicial: "") { modelo in
                guard !modelo.isEmpty else { throw ErrorAdmin("Escribe un modelo.") }
                guard !modelos.contains(modelo) else { throw ErrorAdmin("Ese modelo ya existe.") }
                try await store.guardarModelosCelular(marca: marca, modelos: modelos + [modelo])
                store.avisar("✓ Modelo agregado")
            }
            .capaDeEstado()
        }
    }
}

private struct ModelosProductoView: View {
    @EnvironmentObject private var store: Store
    let categoria: String
    @State private var editando: ModeloEditado?

    struct ModeloEditado: Identifiable {
        let id: Int   // -1 = new
    }

    private var esAccesorios: Bool { categoria == "Accesorios" }

    private func nombre(_ m: JSON) -> String { m["nombre"]?.text ?? m.text ?? "" }

    var body: some View {
        let modelos = store.catalogoProductos[categoria] ?? []
        List {
            Section {
                if modelos.isEmpty { Text("Sin modelos").foregroundStyle(Tema.apagado) }
                ForEach(modelos.indices, id: \.self) { i in
                    HStack {
                        Text(nombre(modelos[i]))
                        Spacer()
                        if esAccesorios {
                            Text(modelos[i]["precio"]?.number.map { Dinero.texto($0) } ?? "Sin precio")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Tema.acento)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if esAccesorios { editando = ModeloEditado(id: i) } }
                    .swipeActions {
                        Button("Eliminar", role: .destructive) {
                            var lista = modelos
                            lista.remove(at: i)
                            Task { try? await store.guardarModelosProducto(categoria: categoria, modelos: lista) }
                        }
                    }
                }
                Button { editando = ModeloEditado(id: -1) } label: { Label("Agregar modelo", systemImage: "plus") }
            } footer: {
                if esAccesorios { Text("Toca un accesorio para cambiar su precio.") }
            }
            .seccionTema()
        }
        .fondoTema()
        .navigationTitle(categoria)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editando) { item in
            let existente = item.id >= 0 && item.id < modelos.count ? modelos[item.id] : nil
            FormularioNombre(
                titulo: existente == nil ? "Nuevo modelo" : "Editar precio",
                etiqueta: "Modelo",
                inicial: existente.map(nombre) ?? "",
                conPrecio: esAccesorios,
                precioInicial: existente?["precio"]?.text ?? "",
                guardar: { modelo in
                    guard !modelo.isEmpty else { throw ErrorAdmin("Escribe un modelo.") }
                    guard !modelos.contains(where: { nombre($0).lowercased() == modelo.lowercased() }) else { throw ErrorAdmin("Ese modelo ya existe.") }
                    try await store.guardarModelosProducto(categoria: categoria, modelos: modelos + [.string(modelo)])
                    store.avisar("✓ Modelo agregado")
                },
                guardarConPrecio: { modelo, precio in
                    guard !modelo.isEmpty else { throw ErrorAdmin("Escribe un modelo.") }
                    var lista = modelos
                    let valor = JSON.object(["nombre": .string(modelo), "precio": .number(precio)])
                    if item.id >= 0, item.id < lista.count {
                        lista[item.id] = valor
                    } else {
                        guard !modelos.contains(where: { nombre($0).lowercased() == modelo.lowercased() }) else { throw ErrorAdmin("Ese modelo ya existe.") }
                        lista.append(valor)
                    }
                    try await store.guardarModelosProducto(categoria: categoria, modelos: lista)
                    store.avisar("✓ Guardado")
                }
            )
            .capaDeEstado()
        }
    }
}

// MARK: - Blocking days

struct DiasBloqueoView: View {
    @EnvironmentObject private var store: Store
    @State private var valores: [String: Int] = [:]
    @State private var confirmacion: Confirmacion?

    private static let titulos = ["activos": "Clientes activos (recordatorios)", "sinrenovar": "Sin renovar", "prospectos": "Prospectos",
                                  "porfinalizar": "Por finalizar", "pr-aprobadas": "PR aprobadas"]

    var body: some View {
        List {
            Section {
                ForEach(Envios.DiasBloqueo.categorias, id: \.self) { clave in
                    Stepper(value: Binding(get: { valores[clave] ?? 7 }, set: { valores[clave] = $0 }), in: 7...21) {
                        HStack {
                            Text(DiasBloqueoView.titulos[clave] ?? clave)
                            Spacer()
                            Text("\(valores[clave] ?? 7) días").font(.system(size: 14, weight: .semibold)).foregroundStyle(Tema.acento)
                        }
                    }
                }
            } footer: {
                Text("Al enviar un mensaje, el contacto queda bloqueado en esa categoría durante estos días. Se puede desbloquear manualmente.")
            }
            .seccionTema()
            Section {
                Button("Limpiar todos los enviados", role: .destructive) {
                    let total = store.contactosConEnvios
                    guard total > 0 else { return store.avisar("No hay enviados registrados.") }
                    confirmacion = Confirmacion(
                        titulo: "Limpiar enviados",
                        mensaje: "¿Eliminar el historial de enviados de \(total) contacto\(total == 1 ? "" : "s")? Todos volverán a aparecer disponibles en las listas de envío.",
                        boton: "Limpiar todo", destructivo: true
                    ) {
                        if await store.limpiarEnviados() { store.avisar("✓ Historial de \(total) contactos limpiado") }
                    }
                }
            }
            .seccionTema()
        }
        .fondoTema()
        .navigationTitle("Días de bloqueo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    Task {
                        do {
                            try await store.guardarDiasBloqueo(Dictionary(uniqueKeysWithValues: Envios.DiasBloqueo.categorias.map { ($0, valores[$0] ?? 7) }))
                            store.avisar("✓ Días de bloqueo guardados")
                        } catch {
                            store.avisar(error.localizedDescription, advertencia: true)
                        }
                    }
                }
                .bold()
            }
        }
        .onAppear {
            valores = Dictionary(uniqueKeysWithValues: Envios.DiasBloqueo.categorias.map { ($0, store.diasBloqueo.dias($0)) })
        }
        .confirmacion($confirmacion)
    }
}

// MARK: - Audit

struct AuditoriaView: View {
    @EnvironmentObject private var store: Store
    @State private var eventos: [EventoAuditoria] = []
    @State private var cargando = false
    @State private var error = ""
    @State private var usuario = ""
    @State private var busqueda = ""

    private static let etiquetas = [
        "cambio_confirmado": "Cambio guardado", "usuario_guardado": "Usuario guardado", "usuario_desactivado": "Usuario desactivado",
        "login_exitoso": "Inicio de sesión", "login_fallido": "Inicio fallido", "cierre_sesion": "Cerró sesión",
        "cliente_creado": "Cliente creado", "cliente_editado": "Cliente editado", "cliente_eliminado": "Cliente eliminado",
        "pago_confirmado": "Pago confirmado", "pago_revertido": "Pago revertido", "pago_no_pagado": "No pagado",
    ]

    private static let formato: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_MX")
        formatter.dateFormat = "d MMM yyyy · HH:mm"
        return formatter
    }()

    private var filtrados: [EventoAuditoria] {
        let q = busqueda.lowercased().trimmingCharacters(in: .whitespaces)
        return eventos.filter { e in
            if !usuario.isEmpty, e.usuarioId != usuario { return false }
            if q.isEmpty { return true }
            return resumen(e).lowercased().contains(q) || nombreUsuario(e.usuarioId).lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Usuario", selection: $usuario) {
                    Text("Todos").tag("")
                    ForEach(store.usuarios) { Text($0.nombre).tag($0.id) }
                }
                TextField("Buscar cliente o detalle", text: $busqueda)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text(cargando ? "Cargando…" : "Últimos \(eventos.count) eventos · \(filtrados.count) visibles")
            }
            .seccionTema()
            if !error.isEmpty {
                Text(error).foregroundStyle(Tema.peligro).seccionTema()
            }
            Section {
                ForEach(filtrados.prefix(300)) { e in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(AuditoriaView.etiquetas[e.tipo] ?? e.tipo).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            Text(AuditoriaView.formato.string(from: Date(timeIntervalSince1970: e.ts / 1000)))
                                .font(.system(size: 11)).foregroundStyle(Tema.apagado)
                        }
                        Text(nombreUsuario(e.usuarioId)).font(Tipo.detalle).foregroundStyle(Tema.acento)
                        let texto = resumen(e)
                        if !texto.isEmpty {
                            Text(texto).font(Tipo.detalle).foregroundStyle(Tema.apagado).lineLimit(3)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .seccionTema()
        }
        .fondoTema()
        .navigationTitle("Auditoría")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await cargar() }
        .task { if eventos.isEmpty { await cargar() } }
    }

    private func cargar() async {
        cargando = true
        defer { cargando = false }
        do {
            eventos = try await store.cargarAuditoria()
            error = ""
        } catch {
            self.error = "No se pudo cargar: \(error.localizedDescription)"
        }
    }

    private func nombreUsuario(_ id: String?) -> String {
        guard let id else { return "—" }
        return store.usuarios.first { $0.id == id }?.nombre ?? "Usuario \(id.prefix(6))"
    }

    /// Which records a change touched, with client names when they still exist.
    private func resumen(_ e: EventoAuditoria) -> String {
        if let registros = e.detalles["registros"]?.list {
            let acciones = ["create": "alta", "update": "cambio", "delete": "baja"]
            return registros.prefix(4).map { r in
                let id = r["id"]?.text ?? ""
                let nombre = store.cliente(id)?.nombre ?? id
                let campos = (r["campos"]?.list ?? []).compactMap(\.text).filter { $0 != "_rev" }.prefix(3).joined(separator: ", ")
                return "\(acciones[r["accion"]?.text ?? ""] ?? "") \(nombre)\(campos.isEmpty ? "" : " (\(campos))")"
            }.joined(separator: " · ") + (registros.count > 4 ? " y \(registros.count - 4) más" : "")
        }
        let partes = ["nombre", "username", "sl", "numPR"].compactMap { e.detalles[$0]?.text }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Password

struct CambiarContrasenaView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("faceIDActivo") private var faceIDActivo = false
    @State private var actual = ""
    @State private var nueva = ""
    @State private var confirmar = ""
    @State private var error = ""
    @State private var guardando = false

    var body: some View {
        Form {
            Section {
                SecureField("Contraseña actual", text: $actual).textContentType(.password)
                SecureField("Nueva contraseña", text: $nueva).textContentType(.newPassword)
                SecureField("Confirmar nueva contraseña", text: $confirmar).textContentType(.newPassword)
            }
            .seccionTema()
            if !error.isEmpty { Text(error).foregroundStyle(Tema.peligro).seccionTema() }
        }
        .fondoTema()
        .navigationTitle("Cambiar contraseña")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { Task { await guardar() } }.bold().disabled(guardando)
            }
        }
    }

    private func guardar() async {
        guard nueva == confirmar else { error = "Las contraseñas no coinciden."; return }
        guardando = true
        defer { guardando = false }
        do {
            try await store.cambiarContrasena(actual: actual, nueva: nueva)
            if faceIDActivo, let usuario = store.usuario {
                Llavero.guardar(usuario: usuario.username.lowercased(), contrasena: nueva)
            }
            store.avisar("✓ Contraseña actualizada")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
