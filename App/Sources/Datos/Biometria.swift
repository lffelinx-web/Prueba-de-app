import Foundation
import LocalAuthentication
import Security
import SwiftUI
import UIKit

/// Face ID / Touch ID through LocalAuthentication.
enum Biometria {
    static var disponible: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// "Face ID", "Touch ID" or "Optic ID", for labels.
    static var nombre: String {
        let contexto = LAContext()
        _ = contexto.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch contexto.biometryType {
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Face ID"
        }
    }

    static var icono: String {
        nombre == "Touch ID" ? "touchid" : "faceid"
    }

    /// Asks for the user's face or finger. The returned context unlocks the stored credentials
    /// without a second prompt.
    static func autenticar(_ motivo: String, cancelar: String = "Usar contraseña") async -> LAContext? {
        let contexto = LAContext()
        contexto.localizedCancelTitle = cancelar
        do {
            try await contexto.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: motivo)
            return contexto
        } catch {
            return nil
        }
    }
}

/// Username and password in the Keychain, readable only after Face ID on this device.
enum Llavero {
    private static let servicio = "com.lfaz.centrodedatos.acceso"
    private static let cuenta = "credenciales"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: servicio, kSecAttrAccount as String: cuenta]
    }

    @discardableResult
    static func guardar(usuario: String, contrasena: String) -> Bool {
        borrar()
        guard let acceso = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil),
              let datos = try? JSONEncoder().encode([usuario, contrasena]) else { return false }
        var consulta = base
        consulta[kSecValueData as String] = datos
        consulta[kSecAttrAccessControl as String] = acceso
        return SecItemAdd(consulta as CFDictionary, nil) == errSecSuccess
    }

    static func leer(con contexto: LAContext) -> (usuario: String, contrasena: String)? {
        var consulta = base
        consulta[kSecReturnData as String] = true
        consulta[kSecMatchLimit as String] = kSecMatchLimitOne
        consulta[kSecUseAuthenticationContext as String] = contexto
        var resultado: CFTypeRef?
        guard SecItemCopyMatching(consulta as CFDictionary, &resultado) == errSecSuccess,
              let datos = resultado as? Data,
              let partes = try? JSONDecoder().decode([String].self, from: datos), partes.count == 2 else { return nil }
        return (partes[0], partes[1])
    }

    /// Whether credentials are stored, checked without showing Face ID.
    static var existe: Bool {
        let contexto = LAContext()
        contexto.interactionNotAllowed = true
        var consulta = base
        consulta[kSecUseAuthenticationContext as String] = contexto
        let estado = SecItemCopyMatching(consulta as CFDictionary, nil)
        return estado == errSecSuccess || estado == errSecInteractionNotAllowed
    }

    static func borrar() {
        SecItemDelete(base as CFDictionary)
    }
}

/// Shows the lock screen in its own window, above any sheet that is open.
@MainActor
enum VentanaBloqueo {
    private static var ventana: UIWindow?

    static func mostrar<Contenido: View>(_ contenido: Contenido) {
        guard ventana == nil else { return }
        let escenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let escena = escenas.first(where: { $0.activationState == .foregroundActive }) ?? escenas.first else { return }
        let nueva = UIWindow(windowScene: escena)
        nueva.windowLevel = .alert + 1
        let controlador = UIHostingController(rootView: contenido)
        controlador.view.backgroundColor = .clear
        nueva.rootViewController = controlador
        nueva.makeKeyAndVisible()
        ventana = nueva
    }

    static func ocultar() {
        guard let actual = ventana else { return }
        actual.isHidden = true
        ventana = nil
        actual.windowScene?.windows.first { $0 !== actual && !$0.isHidden }?.makeKey()
    }
}
