import Combine
import FirebaseCore
import SwiftUI

@main
struct CentroDeDatosApp: App {
    /// Unit tests run inside the app; they must not start Firebase or the UI.
    private let enPruebas = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        guard !enPruebas else { return }
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        } else {
            FirebaseApp.configure(options: CentroDeDatosApp.opcionesWeb)
        }
    }

    /// The web app's project settings, used until the iOS app's GoogleService-Info.plist is added.
    private static var opcionesWeb: FirebaseOptions {
        let opciones = FirebaseOptions(googleAppID: "1:46013374733:ios:0000000000000000", gcmSenderID: "46013374733")
        opciones.apiKey = "AIzaSyAcdnWJr4jyKLAjla0g7MbYHwPHK5VLUbE"
        opciones.projectID = "basededatos-29c60"
        opciones.databaseURL = "https://basededatos-29c60-default-rtdb.firebaseio.com"
        opciones.storageBucket = "basededatos-29c60.firebasestorage.app"
        opciones.bundleID = Bundle.main.bundleIdentifier ?? "com.lfaz.centrodedatos"
        return opciones
    }

    var body: some Scene {
        WindowGroup {
            if enPruebas {
                Text("Pruebas")
            } else {
                AppRaiz()
            }
        }
    }
}

private struct AppRaiz: View {
    @StateObject private var store = Store()
    @StateObject private var bloqueo = Bloqueo()
    /// Same preference as the web app's `ca_theme`: dark unless the user picks light.
    @AppStorage("temaClaro") private var temaClaro = false

    var body: some View {
        RootView()
            .environmentObject(store)
            .environmentObject(bloqueo)
            .tint(Tema.acento)
            .preferredColorScheme(temaClaro ? .light : .dark)
            // Large system text sizes broke the cards; data rows use the fixed scale in `Tipo`.
            .dynamicTypeSize(.xSmall ... .large)
    }
}

struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var bloqueo: Bloqueo
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("temaClaro") private var temaClaro = false
    @AppStorage("faceIDActivo") private var faceIDActivo = false
    @AppStorage("faceIDPreguntado") private var faceIDPreguntado = false

    private let reloj = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Tema.fondo.ignoresSafeArea()
            switch store.fase {
            case .cargando:
                ProgressView()
            case .login:
                LoginView()
            case .app:
                if store.pinCargado {
                    PrincipalView()
                } else {
                    ProgressView("Cargando…")
                }
            }
        }
        .capaDeEstado()
        .background(DetectorActividad { bloqueo.registrarActividad() })
        .onChange(of: store.pinCargado) { _, cargado in
            if cargado { bloqueo.pinCargado(existe: store.pinHash != nil) }
            sincronizarBloqueo()
        }
        .onChange(of: store.fase) { _, fase in
            if fase != .app { bloqueo.reiniciar() }
            sincronizarBloqueo()
        }
        .onChange(of: bloqueo.estado) { _, _ in sincronizarBloqueo() }
        .alert("¿Entrar con \(Biometria.nombre)?", isPresented: Binding(
            get: { ofrecerBiometria },
            set: { if !$0 { bloqueo.credencialesParaBiometria = nil } }
        )) {
            Button("Activar") {
                if let credenciales = bloqueo.credencialesParaBiometria,
                   Llavero.guardar(usuario: credenciales.usuario, contrasena: credenciales.contrasena) {
                    faceIDActivo = true
                    store.avisar("✓ \(Biometria.nombre) activado")
                }
                faceIDPreguntado = true
                bloqueo.credencialesParaBiometria = nil
            }
            Button("Ahora no", role: .cancel) {
                faceIDPreguntado = true
                bloqueo.credencialesParaBiometria = nil
            }
        } message: {
            Text("La próxima vez entrarás sin escribir tu contraseña, y \(Biometria.nombre) también desbloqueará la app en lugar del PIN. Puedes cambiarlo en Ajustes.")
        }
        .onReceive(reloj) { _ in revisarInactividad() }
        .onChange(of: scenePhase) { _, fase in
            if fase == .active { revisarInactividad() }
        }
        .sheet(item: Binding(
            get: { store.revisarPagosDe.map(IdCliente.init) },
            set: { store.revisarPagosDe = $0?.id }
        )) { item in
            PagosPasadosView(clienteId: item.id)
        }
    }

    /// Asked once, after the first sign-in and once the app is unlocked.
    private var ofrecerBiometria: Bool {
        bloqueo.credencialesParaBiometria != nil && store.fase == .app && store.pinCargado && bloqueo.estado == .libre
    }

    private func sincronizarBloqueo() {
        if store.fase == .app, store.pinCargado, bloqueo.estado != .libre {
            VentanaBloqueo.mostrar(
                PantallaPin()
                    .environmentObject(store)
                    .environmentObject(bloqueo)
                    .tint(Tema.acento)
                    .preferredColorScheme(temaClaro ? .light : .dark)
                    .dynamicTypeSize(.xSmall ... .large)
            )
        } else {
            VentanaBloqueo.ocultar()
        }
    }

    private func revisarInactividad() {
        guard store.fase == .app, store.pinCargado else { return }
        if bloqueo.revisarInactividad(tienePin: store.pinHash != nil) {
            store.cerrarSesion()
        }
    }
}

struct IdCliente: Identifiable, Hashable {
    let id: String
}

struct LoginView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var bloqueo: Bloqueo

    @State private var usuario = ""
    @State private var contrasena = ""
    @State private var verificando = false
    @State private var intentos = 0
    @State private var bloqueadoHasta = Date.distantPast
    @State private var intentoAutomatico = false
    @AppStorage("faceIDActivo") private var faceIDActivo = false
    @AppStorage("faceIDPreguntado") private var faceIDPreguntado = false
    @FocusState private var enfoque: Campo?

    private enum Campo { case usuario, contrasena }

    private var conBiometria: Bool { faceIDActivo && Biometria.disponible && Llavero.existe }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cylinder.split.1x2.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            VStack(spacing: 4) {
                Text("Sistema de datos").font(.largeTitle.bold())
                Text("Base de registros").foregroundStyle(Tema.apagado)
            }
            VStack(spacing: 12) {
                TextField("Usuario", text: $usuario)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($enfoque, equals: .usuario)
                    .submitLabel(.next)
                    .onSubmit { enfoque = .contrasena }
                Divider().overlay(Tema.borde)
                SecureField("Contraseña", text: $contrasena)
                    .textContentType(.password)
                    .focused($enfoque, equals: .contrasena)
                    .submitLabel(.go)
                    .onSubmit { Task { await entrar() } }
            }
            .padding(12)
            .background(Tema.superficie, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tema.borde, lineWidth: 1))

            Button {
                Task { await entrar() }
            } label: {
                Group {
                    if verificando { ProgressView() } else { Text("Entrar").bold() }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .foregroundStyle(.white)
            .disabled(verificando)

            if conBiometria {
                Button {
                    Task { await entrarConBiometria() }
                } label: {
                    Label("Entrar con \(Biometria.nombre)", systemImage: Biometria.icono)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pastilla(Tema.acento))
                .disabled(verificando)
            }

            Text(store.errorLogin)
                .font(.footnote)
                .foregroundStyle(Paleta.peligro)
                .multilineTextAlignment(.center)
            Spacer()
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: 460)
        .task {
            guard conBiometria, !intentoAutomatico else { return }
            intentoAutomatico = true
            await entrarConBiometria()
        }
    }

    private func entrarConBiometria() async {
        guard let contexto = await Biometria.autenticar("Entra a Centro de datos"),
              let credenciales = Llavero.leer(con: contexto) else { return }
        usuario = credenciales.usuario
        contrasena = credenciales.contrasena
        await entrar(conBiometria: true)
    }

    private func entrar(conBiometria: Bool = false) async {
        if Date() < bloqueadoHasta {
            store.errorLogin = "🔒 Bloqueado. Espera \(Int(bloqueadoHasta.timeIntervalSinceNow.rounded(.up))) segundos."
            return
        }
        let nombre = usuario.trimmingCharacters(in: .whitespaces).lowercased()
        guard !nombre.isEmpty, !contrasena.isEmpty else {
            store.errorLogin = "Ingresa usuario y contraseña."
            return
        }
        verificando = true
        store.errorLogin = "Verificando..."
        bloqueo.sesionNueva = true
        defer { verificando = false }
        do {
            try await store.iniciarSesion(usuario: nombre, contrasena: contrasena)
            intentos = 0
            if faceIDActivo {
                // Keeps the stored password current when it was typed by hand.
                if !conBiometria { Llavero.guardar(usuario: nombre, contrasena: contrasena) }
            } else if !faceIDPreguntado, Biometria.disponible {
                bloqueo.credencialesParaBiometria = (nombre, contrasena)
            }
            contrasena = ""
        } catch {
            bloqueo.sesionNueva = false
            if conBiometria, [17004, 17009].contains((error as NSError).code) {
                // The password changed elsewhere: the stored one is useless.
                Llavero.borrar()
                faceIDActivo = false
                contrasena = ""
                store.errorLogin = "Tu contraseña cambió. Entra con la nueva para volver a activar \(Biometria.nombre)."
                return
            }
            store.errorLogin = mensaje(para: error)
        }
    }

    /// Firebase Auth error codes (FIRAuthErrorCode), compared by number so any SDK version works.
    private func mensaje(para error: Error) -> String {
        switch (error as NSError).code {
        case 17010:
            return "🔒 Demasiados intentos. Intenta más tarde."
        case 17004, 17008, 17009, 17011:
            intentos += 1
            if intentos >= 5 {
                intentos = 0
                bloqueadoHasta = Date().addingTimeInterval(5 * 60)
                return "🔒 Demasiados intentos. Bloqueado por 5 minutos."
            }
            let restantes = 5 - intentos
            return "Usuario o contraseña incorrectos. (\(restantes) intento\(restantes == 1 ? "" : "s") restante)"
        case 17020:
            return "Sin conexión a internet."
        default:
            return "Error al iniciar sesión."
        }
    }
}
