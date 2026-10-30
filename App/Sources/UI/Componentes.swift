import CoreImage.CIFilterBuiltins
import SwiftUI

enum Paleta {
    static let exito = Color.green
    static let advertencia = Color.orange
    static let peligro = Color.red
    static let macro = Color.accentColor
    static let doble = Color.purple
}

struct Etiqueta: View {
    let texto: String
    var color: Color = .secondary

    init(_ texto: String, color: Color = .secondary) {
        self.texto = texto
        self.color = color
    }

    var body: some View {
        Text(texto)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }
}

struct EtiquetaEstatus: View {
    let estatus: Estatus

    var body: some View {
        switch estatus {
        case .alCorriente: Etiqueta(estatus.titulo, color: Paleta.exito)
        case .atraso: Etiqueta(estatus.titulo, color: Paleta.advertencia)
        case .fraude: Etiqueta(estatus.titulo, color: Paleta.peligro)
        }
    }
}

enum WhatsApp {
    /// The web app always prefixes Mexico's country code.
    static func url(_ tel: String) -> URL? {
        URL(string: "https://wa.me/52" + Texto.soloDigitos(tel))
    }

    static func url(_ tel: String, mensaje: String) -> URL? {
        let numero = Texto.soloDigitos(tel)
        let completo = numero.count == 10 ? "52" + numero : numero
        var partes = URLComponents(string: "https://wa.me/" + completo)
        partes?.queryItems = [URLQueryItem(name: "text", value: mensaje)]
        return partes?.url
    }
}

struct BotonWhatsApp: View {
    let cliente: Cliente
    var compacto = false

    var body: some View {
        if cliente.tieneTelefonoWA, let url = WhatsApp.url(cliente.tel) {
            Link(destination: url) {
                Label(compacto ? "WA" : "WhatsApp", systemImage: "message.fill")
            }
            .buttonStyle(.bordered)
            .tint(.green)
        } else if !compacto {
            Label("Sin WhatsApp", systemImage: "nosign")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

struct FilaDato: View {
    let titulo: String
    let valor: String
    var monoespaciado = false

    init(_ titulo: String, _ valor: String?, monoespaciado: Bool = false) {
        self.titulo = titulo
        self.valor = (valor?.isEmpty ?? true) ? "—" : valor!
        self.monoespaciado = monoespaciado
    }

    var body: some View {
        LabeledContent(titulo) {
            Text(valor)
                .font(monoespaciado ? .body.monospaced() : .body)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct CodigoQR: View {
    let texto: String

    var body: some View {
        if let imagen = CodigoQR.generar(texto) {
            Image(uiImage: imagen)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 170, height: 170)
                .padding(10)
                .background(.white, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    static func generar(_ texto: String) -> UIImage? {
        let filtro = CIFilter.qrCodeGenerator()
        filtro.message = Data(texto.utf8)
        filtro.correctionLevel = "M"
        guard let salida = filtro.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let imagen = CIContext().createCGImage(salida, from: salida.extent) else { return nil }
        return UIImage(cgImage: imagen)
    }
}

// MARK: - Confirmations

struct Confirmacion: Identifiable {
    let id = UUID()
    let titulo: String
    let mensaje: String
    let boton: String
    var destructivo = false
    let accion: () async -> Void
}

extension View {
    func confirmacion(_ item: Binding<Confirmacion?>) -> some View {
        alert(
            item.wrappedValue?.titulo ?? "",
            isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
            presenting: item.wrappedValue
        ) { confirmacion in
            Button(confirmacion.boton, role: confirmacion.destructivo ? .destructive : nil) {
                Task { await confirmacion.accion() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { confirmacion in
            Text(confirmacion.mensaje)
        }
    }

    /// Toast and "Guardando…" cover. Applied at the root and inside each sheet, since a sheet hides the root.
    func capaDeEstado() -> some View {
        modifier(CapaEstado())
    }
}

private struct CapaEstado: ViewModifier {
    @EnvironmentObject private var store: Store

    func body(content: Content) -> some View {
        content
            .overlay {
                if store.guardando {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("Guardando…")
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let aviso = store.aviso {
                    Text(aviso.texto)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundStyle(aviso.advertencia ? Color.white : Color.primary)
                        .background(aviso.advertencia ? AnyShapeStyle(Paleta.peligro.opacity(0.9)) : AnyShapeStyle(.regularMaterial), in: Capsule())
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture { store.aviso = nil }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: store.aviso)
            .task(id: store.aviso?.id) {
                guard let aviso = store.aviso else { return }
                try? await Task.sleep(for: .seconds(aviso.advertencia ? 4.5 : 2.8))
                if store.aviso?.id == aviso.id { store.aviso = nil }
            }
    }
}
