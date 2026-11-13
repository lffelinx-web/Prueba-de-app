import UIKit

/// Photos to PDF: one page per photo, each page the photo's own size.
/// Photos are resized to at most `ladoMaximo` pixels on the long side and stored as JPEG,
/// sharp enough to read documents and light enough to send by WhatsApp.
enum PDF {
    static let ladoMaximo: CGFloat = 2000
    static let calidad: CGFloat = 0.75

    /// Upright, resized JPEG of a photo.
    static func preparar(_ imagen: UIImage) -> Data? {
        let ancho = imagen.size.width, alto = imagen.size.height
        guard ancho > 0, alto > 0 else { return nil }
        let escala = min(1, ladoMaximo / max(ancho * imagen.scale, alto * imagen.scale))
        let destino = CGSize(width: (ancho * imagen.scale * escala).rounded(), height: (alto * imagen.scale * escala).rounded())
        let formato = UIGraphicsImageRendererFormat()
        formato.scale = 1
        formato.opaque = true
        let plana = UIGraphicsImageRenderer(size: destino, format: formato).image { _ in
            imagen.draw(in: CGRect(origin: .zero, size: destino))
        }
        return plana.jpegData(compressionQuality: calidad)
    }

    /// The PDF, from JPEGs made by `preparar`. Each page measures the photo in pixels at 144 ppi.
    static func crear(_ fotos: [Data]) -> Data {
        let paginas = fotos.compactMap(UIImage.init(data:))
        let primera = paginas.first.map { tamano($0) } ?? CGSize(width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: primera))
        return renderer.pdfData { contexto in
            for imagen in paginas {
                let rect = CGRect(origin: .zero, size: tamano(imagen))
                contexto.beginPage(withBounds: rect, pageInfo: [:])
                imagen.draw(in: rect)
            }
        }
    }

    private static func tamano(_ imagen: UIImage) -> CGSize {
        CGSize(width: imagen.size.width * imagen.scale / 2, height: imagen.size.height * imagen.scale / 2)
    }

    /// "Fotos 13-11-2026" style default name, and a safe file name.
    static func nombreArchivo(_ nombre: String) -> String {
        let limpio = nombre.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (limpio.isEmpty ? "Fotos" : limpio) + ".pdf"
    }
}
