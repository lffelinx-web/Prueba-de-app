import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Screen lock with the user's 4-digit PIN: after 10 minutes without touches, and when the app
/// opens with a session kept from before. Without a PIN the session closes instead, like the web.
@MainActor
final class Bloqueo: ObservableObject {
    enum Estado { case libre, bloqueado, configurando }

    @Published private(set) var estado: Estado = .libre
    /// Set by the login screen so a fresh sign-in is not locked right away.
    var sesionNueva = false
    /// Credentials typed at the last sign-in, offered for Face ID once the app is unlocked.
    @Published var credencialesParaBiometria: (usuario: String, contrasena: String)?

    static let inactividad: TimeInterval = 10 * 60
    private var ultimaActividad = Date()

    func registrarActividad() {
        ultimaActividad = Date()
    }

    /// Called once the user's PIN record has loaded.
    func pinCargado(existe: Bool) {
        if !existe {
            estado = .configurando
        } else if !sesionNueva {
            estado = .bloqueado
        }
        sesionNueva = false
        ultimaActividad = Date()
    }

    /// Returns true when the session has to close because there is no PIN to lock with.
    func revisarInactividad(tienePin: Bool) -> Bool {
        guard estado == .libre, Date().timeIntervalSince(ultimaActividad) >= Bloqueo.inactividad else { return false }
        guard tienePin else { return true }
        estado = .bloqueado
        return false
    }

    func bloquear() { estado = .bloqueado }

    func desbloquear() {
        estado = .libre
        ultimaActividad = Date()
    }

    func reiniciar() {
        estado = .libre
        sesionNueva = false
        credencialesParaBiometria = nil
    }
}

/// Watches every touch in the window, including sheets, without interfering with them.
struct DetectorActividad: UIViewRepresentable {
    let alTocar: () -> Void

    func makeUIView(context: Context) -> Vista {
        let vista = Vista()
        vista.alTocar = alTocar
        vista.isUserInteractionEnabled = false
        return vista
    }

    func updateUIView(_ vista: Vista, context: Context) {
        vista.alTocar = alTocar
    }

    final class Vista: UIView {
        var alTocar: () -> Void = {}
        private var gesto: Gesto?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window, gesto == nil else { return }
            let nuevo = Gesto(target: nil, action: nil)
            nuevo.cancelsTouchesInView = false
            nuevo.delaysTouchesBegan = false
            nuevo.delaysTouchesEnded = false
            nuevo.alTocar = { [weak self] in self?.alTocar() }
            window.addGestureRecognizer(nuevo)
            gesto = nuevo
        }
    }

    final class Gesto: UIGestureRecognizer {
        var alTocar: () -> Void = {}

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            alTocar()
            state = .failed
        }
    }
}

struct PantallaPin: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var bloqueo: Bloqueo

    @State private var digitos = ""
    @State private var primerIngreso = ""
    @State private var subtitulo = ""
    @State private var error = ""
    @State private var intentos = 0
    @State private var bloqueadoHasta = Date.distantPast
    @AppStorage("faceIDActivo") private var faceIDActivo = false

    private var configurando: Bool { bloqueo.estado == .configurando }
    private var conBiometria: Bool { faceIDActivo && !configurando && Biometria.disponible }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(configurando ? "Crea tu PIN" : "Sesión bloqueada")
                .font(.title2.bold())
            Text(subtitulo.isEmpty ? (configurando ? "Crea tu PIN de 4 dígitos" : "Ingresa tu PIN para continuar") : subtitulo)
                .foregroundStyle(.secondary)
            HStack(spacing: 18) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.secondary, lineWidth: 1.5)
                        .background(Circle().fill(i < digitos.count ? Color.accentColor : .clear))
                        .frame(width: 16, height: 16)
                }
            }
            Text(error)
                .font(.footnote)
                .foregroundStyle(Paleta.peligro)
                .frame(minHeight: 18)
            teclado
            if conBiometria {
                Button {
                    Task { await desbloquearConBiometria() }
                } label: {
                    Label("Usar \(Biometria.nombre)", systemImage: Biometria.icono)
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.pastilla(Tema.acento))
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tema.fondo)
        .task {
            if conBiometria { await desbloquearConBiometria() }
        }
    }

    private func desbloquearConBiometria() async {
        guard await Biometria.autenticar("Desbloquea Centro de datos", cancelar: "Usar PIN") != nil else { return }
        intentos = 0
        digitos = ""
        bloqueo.desbloquear()
    }

    private var teclado: some View {
        let filas = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["Salir", "0", "⌫"]]
        return VStack(spacing: 14) {
            ForEach(filas, id: \.self) { fila in
                HStack(spacing: 22) {
                    ForEach(fila, id: \.self) { tecla in
                        Button {
                            pulsar(tecla)
                        } label: {
                            Text(tecla)
                                .font(tecla.count == 1 ? .title : .body.weight(.semibold))
                                .frame(width: 74, height: 74)
                                .foregroundStyle(tecla == "Salir" || tecla == "⌫" ? Paleta.peligro : Tema.texto)
                                .background(Tema.superficie, in: Circle())
                                .overlay(Circle().stroke(Tema.borde, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func pulsar(_ tecla: String) {
        switch tecla {
        case "Salir":
            bloqueo.reiniciar()
            store.cerrarSesion()
        case "⌫":
            digitos = String(digitos.dropLast())
            error = ""
        default:
            guard digitos.count < 4 else { return }
            if Date() < bloqueadoHasta {
                error = "🔒 Bloqueado. Espera \(Int(bloqueadoHasta.timeIntervalSinceNow.rounded(.up)))s."
                return
            }
            digitos += tecla
            if digitos.count == 4 {
                if configurando { Task { await confirmarNuevo() } } else { verificar() }
            }
        }
    }

    private func verificar() {
        if Store.hashPin(digitos) == store.pinHash {
            intentos = 0
            digitos = ""
            bloqueo.desbloquear()
            return
        }
        intentos += 1
        digitos = ""
        if intentos >= 5 {
            bloqueadoHasta = Date().addingTimeInterval(5 * 60)
            intentos = 0
            error = "🔒 Demasiados intentos. Bloqueado 5 min."
        } else {
            let restantes = 5 - intentos
            error = "PIN incorrecto. \(restantes) intento\(restantes == 1 ? "" : "s") restante\(restantes == 1 ? "" : "s")."
        }
    }

    private func confirmarNuevo() async {
        if primerIngreso.isEmpty {
            primerIngreso = digitos
            digitos = ""
            subtitulo = "Confirma tu PIN"
            error = ""
            return
        }
        guard digitos == primerIngreso else {
            primerIngreso = ""
            digitos = ""
            subtitulo = "No coincidió. Intenta de nuevo"
            return
        }
        do {
            try await store.guardarPin(digitos)
            digitos = ""
            primerIngreso = ""
            subtitulo = ""
            bloqueo.desbloquear()
            store.avisar("✓ PIN configurado")
        } catch {
            digitos = ""
            self.error = "No se pudo guardar el PIN: \(error.localizedDescription)"
        }
    }
}
