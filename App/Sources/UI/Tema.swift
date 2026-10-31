import SwiftUI
import UIKit

/// The web app's palette (`:root` and `body.light` in the original HTML), dark by default.
enum Tema {
    static let fondo = dinamico(oscuro: 0x0d1117, claro: 0xf0f4f8)
    static let superficie = dinamico(oscuro: 0x161b22, claro: 0xffffff)
    static let superficie2 = dinamico(oscuro: 0x1c2330, claro: 0xe8edf4)
    static let borde = dinamico(oscuro: 0x30363d, claro: 0xc8d0da)
    static let texto = dinamico(oscuro: 0xe6edf3, claro: 0x1a2030)
    static let apagado = dinamico(oscuro: 0x7d8590, claro: 0x6a7585)
    static let acento = dinamico(oscuro: 0x58a6ff, claro: 0x1a6bc8)
    static let peligro = Color(hex: 0xe05252)
    static let exito = Color(hex: 0x52b788)
    static let advertencia = Color(hex: 0xe0a652)
    static let info = Color(hex: 0x79c0ff)
    static let whatsapp = Color(hex: 0x25d366)
    static let morado = Color(hex: 0xb888f0)

    /// Text on an accent-filled button, as the web's `.btn-gold`.
    static let sobreAcento = Color(hex: 0x0d1117)

    private static func dinamico(oscuro: UInt32, claro: UInt32) -> Color {
        Color(UIColor { rasgos in
            UIColor(hex: rasgos.userInterfaceStyle == .light ? claro : oscuro)
        })
    }
}

/// Fixed type scale so cards keep their layout regardless of the system text size.
enum Tipo {
    /// Screen greeting.
    static let saludo = Font.system(size: 22, weight: .bold)
    /// Card headers ("Pagos pendientes hoy").
    static let encabezado = Font.system(size: 15, weight: .semibold)
    /// Client name, the most important line of a row.
    static let nombre = Font.system(size: 15, weight: .semibold)
    /// Regular data (dates, advisor, amounts).
    static let dato = Font.system(size: 13)
    /// Phone and SL numbers.
    static let numero = Font.system(size: 13, design: .monospaced)
    /// Secondary details and subtitles.
    static let detalle = Font.system(size: 12)
    /// Badges and pill buttons.
    static let etiqueta = Font.system(size: 11, weight: .semibold)
    static let boton = Font.system(size: 12, weight: .semibold)
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension View {
    /// Screen background behind lists and forms.
    func fondoTema() -> some View {
        scrollContentBackground(.hidden).background(Tema.fondo)
    }

    /// Rows of grouped sections on the web's surface colour.
    func seccionTema() -> some View {
        listRowBackground(Tema.superficie)
    }

    /// A list row that shows its content as a standalone card.
    func filaTarjeta() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
    }

    /// The web's `.client-card`: surface, 1px border, rounded corners.
    func tarjeta(borde: Color = Tema.borde, fondo: Color = Tema.superficie) -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fondo, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(borde, lineWidth: 1))
    }
}

/// The web's outlined pill buttons (`.btn-wa`, `.btn-confirm-pay`, `.btn-detail`).
struct EstiloPastilla: ButtonStyle {
    var color: Color = Tema.apagado
    var relleno = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Tipo.boton)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .foregroundStyle(relleno ? Tema.sobreAcento : color)
            .background(relleno ? color : color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(relleno ? 0 : 0.45), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == EstiloPastilla {
    static func pastilla(_ color: Color = Tema.apagado, relleno: Bool = false) -> EstiloPastilla {
        EstiloPastilla(color: color, relleno: relleno)
    }
}

/// Uppercase accent heading with a rule, as the web's `.section-label`.
struct TituloSeccion: View {
    let texto: String

    init(_ texto: String) { self.texto = texto }

    var body: some View {
        Text(texto.uppercased())
            .font(Tipo.etiqueta)
            .tracking(1)
            .foregroundStyle(Tema.acento)
    }
}

/// Icon in a tinted rounded square, as the web's `.dash-icon`.
struct IconoCuadro: View {
    let sistema: String
    let color: Color
    var lado: CGFloat = 36

    var body: some View {
        Image(systemName: sistema)
            .font(.system(size: lado * 0.48, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: lado, height: lado)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: lado * 0.28))
    }
}

/// Phone number on one line, never broken.
struct LineaTelefono: View {
    let tel: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "phone.fill").font(.system(size: 10)).foregroundStyle(Tema.apagado)
            Text(tel.isEmpty ? "Sin tel." : tel).font(Tipo.numero).foregroundStyle(Tema.texto)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// Client name: one line, slightly shrunk before truncating.
struct NombreCliente: View {
    let nombre: String
    var apagado = false

    var body: some View {
        Text(nombre)
            .font(Tipo.nombre)
            .foregroundStyle(apagado ? Tema.apagado : Tema.texto)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .truncationMode(.tail)
    }
}

/// A navigation row inside a plain list without the system chevron outside the card.
struct EnlaceSinFlecha<Contenido: View>: View {
    let valor: Ruta
    @ViewBuilder let contenido: () -> Contenido

    var body: some View {
        ZStack {
            NavigationLink(value: valor) { EmptyView() }.opacity(0)
            contenido()
        }
    }
}
