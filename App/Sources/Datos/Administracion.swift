import FirebaseAuth
import FirebaseCore
import FirebaseDatabase
import Foundation

struct ErrorAdmin: LocalizedError {
    let errorDescription: String?
    init(_ mensaje: String) { errorDescription = mensaje }
}

/// One entry of `ca_auditoria`.
struct EventoAuditoria: Identifiable {
    let id: String
    let ts: Double
    let tipo: String
    let usuarioId: String?
    let detalles: JSON
}

/// Administrator tools (Phase 3), with the same writes the web app's secure layer makes.
extension Store {
    // MARK: - Users

    /// `ca_accesos/<uid>` record whose `perfilId` is the given profile.
    private func acceso(dePerfil perfilId: String) async throws -> (uid: String, valor: [String: JSON]) {
        let snap = try await leer("ca_accesos")
        for (uid, valor) in JSON(firebase: snap.value).object ?? [:] {
            if let datos = valor.object, datos["perfilId"]?.text == perfilId { return (uid, datos) }
        }
        throw ErrorAdmin("Este perfil necesita vincularse a su UID desde Firebase.")
    }

    /// Creates the Firebase Auth account in a secondary app, so the administrator stays signed in.
    func crearUsuario(nombre: String, username: String, rol: String, contrasena: String) async throws {
        guard esAdmin else { throw ErrorAdmin("Solo administradores.") }
        let usuario = username.trimmingCharacters(in: .whitespaces).lowercased()
        let nombre = Texto.limpio(nombre)
        guard !nombre.isEmpty, nombre.count <= 150, usuario.range(of: #"^[a-z0-9_-]{3,50}$"#, options: .regularExpression) != nil,
              ["admin", "usuario"].contains(rol) else { throw ErrorAdmin("Revisa nombre, usuario y rol.") }
        guard contrasena.count >= 12 else { throw ErrorAdmin("La contraseña requiere al menos 12 caracteres.") }

        if FirebaseApp.app(name: "secundaria") == nil, let opciones = FirebaseApp.app()?.options {
            FirebaseApp.configure(name: "secundaria", options: opciones)
        }
        guard let app = FirebaseApp.app(name: "secundaria") else { throw ErrorAdmin("No se pudo preparar el alta.") }
        let auth = Auth.auth(app: app)
        let resultado: AuthDataResult
        do {
            resultado = try await auth.createUser(withEmail: Store.correo(de: usuario), password: contrasena)
        } catch {
            switch (error as NSError).code {
            case 17007: throw ErrorAdmin("Ese nombre de usuario ya está registrado.")
            case 17026: throw ErrorAdmin("Contraseña muy débil.")
            default: throw ErrorAdmin(error.localizedDescription)
            }
        }
        let uid = resultado.user.uid
        defer { try? auth.signOut() }
        do {
            try await actualizar([
                "ca_users/\(uid)": ["id": uid, "nombre": nombre, "username": usuario, "rol": rol, "_rev": 1] as [String: Any],
                "ca_accesos/\(uid)": ["activo": true, "rol": rol == "admin" ? "admin" : "asesor", "perfilId": uid] as [String: Any],
            ])
        } catch {
            try? await resultado.user.delete()
            throw error
        }
        _ = await auditar("usuario_guardado", detalles: .object(["perfilId": "nuevo", "username": .string(usuario)]))
    }

    /// Name and role only; the username never changes and each user changes their own password.
    func editarUsuario(_ id: String, nombre: String, rol: String) async throws {
        guard esAdmin else { throw ErrorAdmin("Solo administradores.") }
        let nombre = Texto.limpio(nombre)
        guard !nombre.isEmpty, nombre.count <= 150, ["admin", "usuario"].contains(rol) else { throw ErrorAdmin("Revisa nombre y rol.") }
        guard let clave = clavesUsuarios[id] else { throw ErrorAdmin("Usuario no encontrado.") }
        let (uid, datos) = try await acceso(dePerfil: id)
        var nuevoAcceso = datos
        nuevoAcceso["rol"] = .string(rol == "admin" ? "admin" : "asesor")
        try await actualizar([
            "ca_users/\(clave)/nombre": nombre,
            "ca_users/\(clave)/rol": rol,
            "ca_users/\(clave)/_rev": (revisionesUsuarios[id] ?? 0) + 1,
            "ca_accesos/\(uid)": JSON.object(nuevoAcceso).firebaseValue,
        ])
        _ = await auditar("usuario_guardado", detalles: .object(["perfilId": .string(id), "username": .string(usuarios.first { $0.id == id }?.username ?? "")]))
    }

    /// Revokes access: the account stays in Firebase Auth but can no longer read anything.
    func desactivarUsuario(_ id: String) async throws {
        guard esAdmin else { throw ErrorAdmin("Solo administradores.") }
        guard id != usuario?.id else { throw ErrorAdmin("No puedes desactivar tu propio usuario.") }
        let (uid, datos) = try await acceso(dePerfil: id)
        var nuevoAcceso = datos
        nuevoAcceso["activo"] = false
        var cambios: [String: Any] = ["ca_accesos/\(uid)": JSON.object(nuevoAcceso).firebaseValue]
        if let clave = clavesUsuarios[id] { cambios["ca_users/\(clave)"] = NSNull() }
        try await actualizar(cambios)
        _ = await auditar("usuario_desactivado", detalles: .object(["perfilId": .string(id)]))
    }

    func cambiarContrasena(actual: String, nueva: String) async throws {
        guard nueva.count >= 6 else { throw ErrorAdmin("Mínimo 6 caracteres.") }
        guard let user = Auth.auth().currentUser, let correo = user.email else { throw ErrorAdmin("Sesión no disponible.") }
        do {
            _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: correo, password: actual))
        } catch {
            throw ErrorAdmin("Contraseña actual incorrecta.")
        }
        do {
            try await user.updatePassword(to: nueva)
        } catch {
            throw ErrorAdmin((error as NSError).code == 17026 ? "La nueva contraseña es muy débil." : error.localizedDescription)
        }
    }

    // MARK: - Advisors

    func guardarAsesor(nombre entrada: String, original: String?) async throws {
        guard esAdmin else { throw ErrorAdmin("Solo administradores.") }
        let nombre = Texto.limpio(entrada)
        guard !nombre.isEmpty else { throw ErrorAdmin("El nombre es requerido.") }
        guard nombre.count <= 30 else { throw ErrorAdmin("Máximo 30 caracteres.") }
        guard !asesores.contains(where: { $0.lowercased() == nombre.lowercased() && $0 != original }) else {
            throw ErrorAdmin("Ya existe un asesor con ese nombre.")
        }
        var lista = asesores
        var cambios: [String: Any] = [:]
        if let original, let i = lista.firstIndex(of: original) {
            lista[i] = nombre
            if nombre != original {
                // Clients keep pointing at the renamed advisor.
                var clientesEditados = clientes
                for j in clientesEditados.indices where clientesEditados[j].asesor == original { clientesEditados[j]["asesor"] = .string(nombre) }
                guard await guardar(clientesEditados, silencioso: true) else { throw ErrorAdmin("No se pudieron actualizar los clientes.") }
                cambios["ca_asesores_visibilidad/\(Store.claveAsesor(nombre))"] = asesorDisponible(original)
                cambios["ca_asesores_visibilidad/\(Store.claveAsesor(original))"] = NSNull()
            }
        } else {
            lista.append(nombre)
        }
        cambios["ca_asesores"] = lista
        try await actualizar(cambios)
    }

    func eliminarAsesor(_ nombre: String) async throws {
        guard esAdmin else { throw ErrorAdmin("Solo administradores.") }
        try await actualizar([
            "ca_asesores": asesores.filter { $0 != nombre },
            "ca_asesores_visibilidad/\(Store.claveAsesor(nombre))": NSNull(),
        ])
    }

    func cambiarDisponibilidad(_ nombre: String, disponible: Bool) async throws {
        guard esAdmin else { throw ErrorAdmin("Solo el administrador puede cambiar esta opción.") }
        try await escribir(raiz.child("ca_asesores_visibilidad").child(Store.claveAsesor(nombre)), disponible)
    }

    // MARK: - Catalogues

    func guardarModelosCelular(marca: String, modelos: [String]) async throws {
        guard esAdmin else { throw ErrorAdmin("Solo administradores.") }
        try await escribir(raiz.child("ca_catalogo_celulares").child(marca), modelos)
    }

    func eliminarMarca(_ marca: String) async throws {
        guard esAdmin else { throw ErrorAdmin("Solo administradores.") }
        try await escribir(raiz.child("ca_catalogo_celulares").child(marca), nil)
    }

    /// Accessories are stored as `{nombre, precio}`; the other categories as plain names.
    func guardarModelosProducto(categoria: String, modelos: [JSON]) async throws {
        guard esAdmin else { throw ErrorAdmin("Solo administradores.") }
        try await escribir(raiz.child("ca_catalogo_productos").child(categoria), JSON.array(modelos).firebaseValue)
    }

    // MARK: - Blocking days and sent marks

    /// Saved on the administrator's own user record, where the web app reads it.
    func guardarDiasBloqueo(_ valores: [String: Int]) async throws {
        guard esAdmin, let id = usuario?.id, let clave = clavesUsuarios[id] else { throw ErrorAdmin("Solo administradores.") }
        guard valores.values.allSatisfy({ (7...21).contains($0) }) else { throw ErrorAdmin("El valor debe estar entre 7 y 21 días.") }
        try await actualizar([
            "ca_users/\(clave)/_diasBloqueoCat": valores,
            "ca_users/\(clave)/_rev": (revisionesUsuarios[id] ?? 0) + 1,
        ])
    }

    var contactosConEnvios: Int {
        clientes.filter { c in
            c["ultimoEnvioMasivo"] != nil || !(c["ultimoEnvioRec"]?.object ?? [:]).isEmpty || !(c["ultimoEnvioSinRenovar"]?.object ?? [:]).isEmpty
        }.count
    }

    /// Every contact becomes available again in every sending list.
    func limpiarEnviados() async -> Bool {
        guard esAdmin else { return false }
        var lista = clientes
        for i in lista.indices {
            lista[i]["ultimoEnvioMasivo"] = nil
            lista[i]["ultimoEnvioRec"] = nil
            lista[i]["ultimoEnvioSinRenovar"] = nil
        }
        return await guardar(lista)
    }

    // MARK: - Audit

    func cargarAuditoria(limite: UInt = 500) async throws -> [EventoAuditoria] {
        let snap: DataSnapshot = try await withCheckedThrowingContinuation { continuacion in
            raiz.child("ca_auditoria").queryOrdered(byChild: "ts").queryLimited(toLast: limite)
                .observeSingleEvent(of: .value, with: { continuacion.resume(returning: $0) }, withCancel: { continuacion.resume(throwing: $0) })
        }
        return snap.children.compactMap { hijo -> EventoAuditoria? in
            guard let hijo = hijo as? DataSnapshot else { return nil }
            let valor = JSON(firebase: hijo.value)
            return EventoAuditoria(
                id: hijo.key,
                ts: valor["ts"]?.number ?? 0,
                tipo: valor["tipo"]?.text ?? "",
                usuarioId: valor["usuario"]?["id"]?.text,
                detalles: valor["detalles"] ?? .null
            )
        }
        .sorted { $0.ts > $1.ts }
    }
}
