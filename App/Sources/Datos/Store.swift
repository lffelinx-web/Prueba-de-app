import Combine
import CryptoKit
import FirebaseAuth
import FirebaseDatabase
import Foundation

struct Usuario: Identifiable, Equatable {
    let id: String
    let nombre: String
    let username: String
    let rol: String

    var iniciales: String {
        String(nombre.split(separator: " ").compactMap(\.first).prefix(2)).uppercased()
    }

    var primerNombre: String { nombre.split(separator: " ").first.map(String.init) ?? nombre }
}

/// `ca_accesos/<uid>`: the server-side permission record the rules check.
struct Acceso: Equatable {
    let activo: Bool
    let rol: String
    let perfilId: String

    var esAdmin: Bool { rol == "admin" }
}

struct Notificacion: Identifiable, Equatable {
    let id: String
    let tipo: String
    let clienteId: String?
    let mensaje: String
    let ts: Double
    let leida: Bool
}

struct Accesorio: Hashable {
    let nombre: String
    let precio: Double
}

struct Aviso: Identifiable, Equatable {
    let id = UUID()
    let texto: String
    let advertencia: Bool
}

/// Session, live data and the only path that writes clients, mirroring the web app's
/// Firebase layer so both can be used side by side on the same database.
@MainActor
final class Store: ObservableObject {
    enum Fase { case cargando, login, app }

    @Published private(set) var fase: Fase = .cargando
    @Published var errorLogin = ""
    @Published private(set) var acceso: Acceso?
    @Published private(set) var usuario: Usuario?
    @Published private(set) var usuarios: [Usuario] = []
    @Published private(set) var clientes: [Cliente] = []
    @Published private(set) var clientesCargados = false
    @Published private(set) var asesores: [String] = []
    @Published private(set) var visibilidadAsesores: [String: Bool] = [:]
    @Published private(set) var visibilidadCargada = false
    @Published private(set) var notificaciones: [Notificacion] = []
    @Published private(set) var guardando = false
    @Published var aviso: Aviso?
    /// A new active client whose first payments are already past, to confirm them right away.
    @Published var revisarPagosDe: String?
    @Published private(set) var pinHash: String?
    @Published private(set) var pinCargado = false
    @Published private(set) var plantillasRecordatorio: [String: JSON] = [:]
    @Published private(set) var mensajesPredeterminados: [String: JSON] = [:]
    @Published private(set) var catalogoCelulares: [String: [String]] = [:]
    @Published private(set) var catalogoProductos: [String: [JSON]] = [:]
    @Published private(set) var diasBloqueo = Envios.DiasBloqueo()

    let raiz: DatabaseReference
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var escuchas: [(DatabaseReference, DatabaseHandle)] = []
    private var accesoRef: (DatabaseReference, DatabaseHandle)?
    private var diferenciasClientes = Diferencias(tabla: "ca_clientes", base: [:], claves: [:], revisiones: [:])
    private var notificacionesCargadas = false
    private var notificacionesOcultas: Set<String> = []
    private var notificacionesPendientes: Set<String> = []
    private var epoca = 0

    var esAdmin: Bool { acceso?.esAdmin == true }

    init() {
        raiz = Database.database().reference()
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.sesionCambio(user) }
        }
    }

    // MARK: - Session

    static func correo(de usuario: String) -> String {
        usuario.trimmingCharacters(in: .whitespaces).lowercased() + "@cartera.app"
    }

    func iniciarSesion(usuario: String, contrasena: String) async throws {
        errorLogin = ""
        _ = try await Auth.auth().signIn(withEmail: Store.correo(de: usuario), password: contrasena)
    }

    func cerrarSesion(mensaje: String = "") {
        epoca += 1
        detenerEscuchas()
        try? Auth.auth().signOut()
        acceso = nil
        usuario = nil
        usuarios = []
        clientes = []
        clientesCargados = false
        asesores = []
        visibilidadAsesores = [:]
        visibilidadCargada = false
        notificaciones = []
        notificacionesCargadas = false
        notificacionesOcultas = []
        notificacionesPendientes = []
        diferenciasClientes = Diferencias(tabla: "ca_clientes", base: [:], claves: [:], revisiones: [:])
        guardando = false
        pinHash = nil
        pinCargado = false
        plantillasRecordatorio = [:]
        mensajesPredeterminados = [:]
        catalogoCelulares = [:]
        catalogoProductos = [:]
        diasBloqueo = Envios.DiasBloqueo()
        errorLogin = mensaje
        fase = .login
    }

    private func sesionCambio(_ user: User?) {
        guard let user else {
            if fase != .login { cerrarSesion(mensaje: errorLogin) }
            return
        }
        guard accesoRef == nil else { return }
        let ref = raiz.child("ca_accesos").child(user.uid)
        var iniciado = false
        let handle = ref.observe(.value, with: { [weak self] snap in
            guard let self else { return }
            let datos = JSON(firebase: snap.value)
            guard datos["activo"] == .bool(true), let rol = datos["rol"]?.text, ["admin", "asesor"].contains(rol),
                  let perfilId = datos["perfilId"]?.text else {
                self.cerrarSesion(mensaje: "Cuenta sin acceso autorizado. Contacta al administrador.")
                return
            }
            self.acceso = Acceso(activo: true, rol: rol, perfilId: perfilId)
            if !iniciado {
                iniciado = true
                self.iniciarEscuchas()
            }
        }, withCancel: { [weak self] _ in
            self?.cerrarSesion(mensaje: "No se pudieron verificar los permisos.")
        })
        accesoRef = (ref, handle)
    }

    private func escuchar(_ ruta: String, _ alCambiar: @escaping (DataSnapshot) -> Void, error: ((Error) -> Void)? = nil) {
        let ref = raiz.child(ruta)
        let epocaActual = epoca
        let handle = ref.observe(.value, with: { [weak self] snap in
            guard let self, self.epoca == epocaActual else { return }
            alCambiar(snap)
        }, withCancel: { [weak self] fallo in
            guard let self, self.epoca == epocaActual else { return }
            error?(fallo)
        })
        escuchas.append((ref, handle))
    }

    private func detenerEscuchas() {
        for (ref, handle) in escuchas { ref.removeObserver(withHandle: handle) }
        escuchas = []
        if let par = accesoRef { par.0.removeObserver(withHandle: par.1) }
        accesoRef = nil
    }

    private func iniciarEscuchas() {
        escuchar("ca_users", { [weak self] snap in self?.recibirUsuarios(snap) }, error: { [weak self] fallo in
            self?.cerrarSesion(mensaje: "⚠️ Error DB: \(fallo.localizedDescription)")
        })
    }

    private func recibirUsuarios(_ snap: DataSnapshot) {
        let registros = hijos(snap)
        // The blocking days live on the administrator's own user record.
        var dias = Envios.DiasBloqueo()
        if let admin = registros.first(where: { $0.1["rol"]?.text == "admin" })?.1, let config = admin["_diasBloqueoCat"]?.object {
            for (clave, valor) in config { if let numero = valor.int, numero > 0 { dias.valores[clave] = numero } }
        }
        diasBloqueo = dias
        usuarios = registros.compactMap { _, valor in
            guard let id = valor["id"]?.text else { return nil }
            return Usuario(id: id, nombre: valor["nombre"]?.text ?? "", username: valor["username"]?.text ?? "", rol: valor["rol"]?.text ?? "usuario")
        }
        guard !usuarios.isEmpty, let acceso, let perfil = usuarios.first(where: { $0.id == acceso.perfilId }) else {
            cerrarSesion(mensaje: "Cuenta sin acceso autorizado. Contacta al administrador.")
            return
        }
        let primeraVez = usuario == nil
        usuario = Usuario(id: perfil.id, nombre: perfil.nombre, username: perfil.username, rol: acceso.esAdmin ? "admin" : "usuario")
        if primeraVez {
            iniciarEscuchasDatos(usuarioId: perfil.id)
            fase = .app
        }
    }

    private func iniciarEscuchasDatos(usuarioId: String) {
        escuchar("ca_asesores") { [weak self] snap in
            self?.asesores = (JSON(firebase: snap.value).list ?? []).compactMap(\.text)
        }
        escuchar("ca_asesores_visibilidad", { [weak self] snap in
            guard let self else { return }
            var mapa: [String: Bool] = [:]
            for (clave, valor) in JSON(firebase: snap.value).object ?? [:] {
                if case .bool(let visible) = valor { mapa[clave] = visible }
            }
            self.visibilidadAsesores = mapa
            self.visibilidadCargada = true
        }, error: { [weak self] _ in
            self?.visibilidadCargada = false
            self?.avisar("No se pudo cargar la disponibilidad de asesores. Revisa las reglas de Firebase.", advertencia: true)
        })
        escuchar("ca_notificaciones") { [weak self] snap in
            guard let self else { return }
            self.notificaciones = self.hijos(snap).map { clave, valor in
                Notificacion(id: clave, tipo: valor["tipo"]?.text ?? "", clienteId: valor["clienteId"]?.text,
                             mensaje: valor["mensaje"]?.text ?? "", ts: valor["ts"]?.number ?? 0, leida: valor["leida"]?.truthy ?? false)
            }
            .sorted { $0.ts > $1.ts }
            self.notificacionesPendientes = []
            self.notificacionesCargadas = true
            self.mantenimientoAutomatico()
        }
        escuchar("ca_clientes") { [weak self] snap in self?.recibirClientes(snap) }
        escuchar("ca_recordatorios_plantillas/\(usuarioId)") { [weak self] snap in
            self?.plantillasRecordatorio = JSON(firebase: snap.value).object ?? [:]
        }
        escuchar("ca_mensajes_pred/\(usuarioId)") { [weak self] snap in
            self?.mensajesPredeterminados = JSON(firebase: snap.value).object ?? [:]
        }
        escuchar("ca_catalogo_celulares") { [weak self] snap in
            var catalogo: [String: [String]] = [:]
            for (marca, modelos) in JSON(firebase: snap.value).object ?? [:] {
                catalogo[marca] = (modelos.list ?? []).compactMap { $0["nombre"]?.text ?? $0.text }
            }
            self?.catalogoCelulares = catalogo
        }
        escuchar("ca_catalogo_productos") { [weak self] snap in
            var catalogo = (JSON(firebase: snap.value).object ?? [:]).mapValues { $0.list ?? [] }
            for categoria in Store.categoriasProducto where catalogo[categoria] == nil { catalogo[categoria] = [] }
            self?.catalogoProductos = catalogo
        }

        raiz.child("ca_pins").child(usuarioId).observeSingleEvent(of: .value) { [weak self] snap in
            self?.pinHash = snap.value as? String
            self?.pinCargado = true
        }
    }

    /// Children in database order, whether the node is stored as an object or as an array.
    private func hijos(_ snap: DataSnapshot) -> [(String, JSON)] {
        snap.children.compactMap { hijo in
            guard let hijo = hijo as? DataSnapshot else { return nil }
            let valor = JSON(firebase: hijo.value)
            return valor.object == nil ? nil : (hijo.key, valor)
        }
    }

    private func recibirClientes(_ snap: DataSnapshot) {
        var base: [String: [String: JSON]] = [:], claves: [String: String] = [:], revisiones: [String: Int] = [:]
        var lista: [Cliente] = []
        for (clave, valor) in hijos(snap) {
            let cliente = Cliente(raw: valor.object ?? [:]).normalizado()
            lista.append(cliente)
            base[cliente.id] = cliente.raw
            claves[cliente.id] = clave
            revisiones[cliente.id] = valor["_rev"]?.int ?? 0
        }
        diferenciasClientes = Diferencias(tabla: "ca_clientes", base: base, claves: claves, revisiones: revisiones)
        clientes = lista
        clientesCargados = true
        mantenimientoAutomatico()
    }

    // MARK: - Writing clients

    /// Writes every difference between `nuevos` and the last snapshot as one atomic update.
    /// The listener then delivers the result, so callers never patch `clientes` themselves.
    @discardableResult
    func guardar(_ nuevos: [Cliente], silencioso: Bool = false) async -> Bool {
        let (cambios, updates) = diferenciasClientes.calcular(nuevos.map(\.raw))
        guard !cambios.isEmpty else { return true }
        guard !guardando else {
            if !silencioso { avisar("Espera a que termine el guardado actual.", advertencia: true) }
            return false
        }
        guard acceso?.activo == true else {
            avisar("No tienes acceso activo.", advertencia: true)
            return false
        }
        let epocaActual = epoca
        guardando = true
        defer { if epoca == epocaActual { guardando = false } }
        do {
            try await actualizar(updates)
            let auditado = await auditar("cambio_confirmado", detalles: .object([
                "tabla": "ca_clientes",
                "registros": .array(cambios.map { cambio in
                    .object([
                        "id": .string(cambio.id),
                        "accion": .string(cambio.accion.rawValue),
                        "campos": .array(cambio.campos.map(JSON.string)),
                    ])
                }),
            ]))
            guard epoca == epocaActual else { return true }
            if !silencioso || !auditado {
                avisar(auditado ? "✓ Guardado confirmado" : "Datos guardados; no se pudo registrar la auditoría.", advertencia: !auditado)
            }
            return true
        } catch {
            guard epoca == epocaActual else { return false }
            // The SDK rolls back rejected writes; reload from the server as well.
            if let snap = try? await leer("ca_clientes") { recibirClientes(snap) }
            avisar("No se guardó el cambio. \(error.localizedDescription) Recarga los datos y vuelve a intentarlo.", advertencia: true)
            return false
        }
    }

    /// Append-only audit entry, as the web app writes it.
    private func auditar(_ tipo: String, detalles: JSON) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid, let acceso else { return false }
        let evento: [String: Any] = [
            "ts": ServerValue.timestamp(),
            "tipo": tipo,
            "usuario": ["uid": uid, "id": acceso.perfilId],
            "detalles": detalles.firebaseValue,
        ]
        do {
            try await escribir(raiz.child("ca_auditoria").childByAutoId(), evento)
            return true
        } catch {
            return false
        }
    }

    func actualizar(_ updates: [String: Any]) async throws {
        try await withCheckedThrowingContinuation { (continuacion: CheckedContinuation<Void, Error>) in
            raiz.updateChildValues(updates) { error, _ in
                if let error { continuacion.resume(throwing: error) } else { continuacion.resume() }
            }
        }
    }

    func escribir(_ ref: DatabaseReference, _ valor: Any?) async throws {
        try await withCheckedThrowingContinuation { (continuacion: CheckedContinuation<Void, Error>) in
            ref.setValue(valor) { error, _ in
                if let error { continuacion.resume(throwing: error) } else { continuacion.resume() }
            }
        }
    }

    func leer(_ ruta: String) async throws -> DataSnapshot {
        try await withCheckedThrowingContinuation { continuacion in
            raiz.child(ruta).observeSingleEvent(of: .value, with: { snap in
                continuacion.resume(returning: snap)
            }, withCancel: { error in
                continuacion.resume(throwing: error)
            })
        }
    }

    // MARK: - Automatic maintenance

    /// Expired credits and PRs are moved by the administrator's session, like on the web.
    private func mantenimientoAutomatico() {
        guard esAdmin, clientesCargados, notificacionesCargadas, !guardando, fase == .app else { return }
        let (nuevos, avisos) = Reglas.mantenimiento(clientes)
        for aviso in avisos { crearNotificacion(aviso.tipo, datos: aviso.datos) }
        if nuevos != clientes {
            Task { await guardar(nuevos, silencioso: true) }
        }
    }

    /// One unread notification per client and type.
    func crearNotificacion(_ tipo: String, datos: [String: JSON]) {
        let clienteId = datos["clienteId"]?.text
        let clave = tipo + "|" + (clienteId ?? "")
        guard !notificaciones.contains(where: { !$0.leida && $0.tipo == tipo && $0.clienteId == clienteId }),
              !notificacionesPendientes.contains(clave) else { return }
        notificacionesPendientes.insert(clave)
        var valor = datos
        valor["tipo"] = .string(tipo)
        valor["ts"] = .number(Double(Fecha.milisegundos()))
        valor["leida"] = false
        let id = "\(Fecha.milisegundos())_\(Identificador.aleatorio(6))"
        raiz.child("ca_notificaciones").child(id).setValue(JSON.object(valor).firebaseValue)
    }

    var notificacionesVisibles: [Notificacion] {
        notificaciones.filter { !notificacionesOcultas.contains($0.id) }
    }

    /// Advisors only hide shared notifications on this device; the administrator deletes them.
    func eliminarNotificacion(_ id: String) {
        if esAdmin {
            raiz.child("ca_notificaciones").child(id).removeValue()
        } else {
            notificacionesOcultas.insert(id)
            objectWillChange.send()
        }
    }

    func eliminarTodasLasNotificaciones() {
        for notificacion in notificacionesVisibles { eliminarNotificacion(notificacion.id) }
    }

    // MARK: - Advisors

    /// Visibility is keyed by the advisor's name in UTF-8 hex.
    static func claveAsesor(_ nombre: String) -> String {
        nombre.utf8.map { String(format: "%02x", $0) }.joined()
    }

    func asesorDisponible(_ nombre: String) -> Bool {
        visibilidadAsesores[Store.claveAsesor(nombre)] != false
    }

    /// Advisors offered in a form: available ones, plus the one already assigned.
    func asesoresParaFormulario(asignado: String?) -> [String] {
        var lista = asesores.filter { asesorDisponible($0) || $0 == asignado }
        if let asignado, !asignado.isEmpty, !lista.contains(asignado) { lista.append(asignado) }
        return lista
    }

    // MARK: - PIN

    static func hashPin(_ pin: String) -> String {
        SHA256.hash(data: Data(("PIN::" + pin).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func guardarPin(_ pin: String) async throws {
        guard let usuario else { return }
        let hash = Store.hashPin(pin)
        try await escribir(raiz.child("ca_pins").child(usuario.id), hash)
        pinHash = hash
    }

    // MARK: - Feedback

    func avisar(_ texto: String, advertencia: Bool = false) {
        aviso = Aviso(texto: texto, advertencia: advertencia)
    }

    func cliente(_ id: String?) -> Cliente? {
        guard let id else { return nil }
        return clientes.first { $0.id == id }
    }

    // MARK: - Templates and catalogues

    static let categoriasProducto = ["iPhone", "Pantallas", "Bicis", "Motos", "Accesorios"]

    /// The user's reminder template, or nil when it has not been written yet.
    func plantillaRecordatorio(_ tipo: TipoRecordatorio) -> PlantillaRecordatorio? {
        let plantilla = PlantillaRecordatorio(plantillasRecordatorio[tipo.rawValue])
        return plantilla.tieneContenido ? plantilla : nil
    }

    func mensajePredeterminado(_ categoria: CategoriaMensaje) -> MensajePredeterminado? {
        guard let valor = mensajesPredeterminados[categoria.rawValue] else { return nil }
        return MensajePredeterminado(valor)
    }

    func guardarPlantilla(_ plantilla: PlantillaRecordatorio, tipo: TipoRecordatorio) async -> Bool {
        guard let usuario else { return false }
        do {
            try await escribir(raiz.child("ca_recordatorios_plantillas").child(usuario.id).child(tipo.rawValue), plantilla.json(tipo: tipo).firebaseValue)
            avisar("✓ Plantilla guardada")
            return true
        } catch {
            avisar("Error al guardar. Intenta de nuevo.", advertencia: true)
            return false
        }
    }

    func guardarMensaje(_ mensaje: MensajePredeterminado, categoria: CategoriaMensaje) async -> Bool {
        guard let usuario else { return false }
        do {
            try await escribir(raiz.child("ca_mensajes_pred").child(usuario.id).child(categoria.rawValue), mensaje.json.firebaseValue)
            avisar("✓ Plantilla guardada")
            return true
        } catch {
            avisar("Error al guardar. Intenta de nuevo.", advertencia: true)
            return false
        }
    }

    /// Accessories with a price, offered in the advanced "macropesos disponibles" reminder.
    var accesoriosConPrecio: [Accesorio] {
        (catalogoProductos["Accesorios"] ?? []).compactMap { modelo in
            guard let nombre = modelo["nombre"]?.text, let precio = modelo["precio"]?.number, precio > 0 else { return nil }
            return Accesorio(nombre: nombre, precio: precio)
        }
    }

    func modelos(de categoria: String) -> [String] {
        (catalogoProductos[categoria] ?? []).compactMap { $0["nombre"]?.text ?? $0.text }
    }
}
