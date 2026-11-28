import Foundation

/// The single product catalogue under `ca_catalogo_productos`, shared with the web app.
/// Celulares and Pantallas are grouped by brand (`{marca: [modelos]}`); the other categories
/// are plain lists, and accessories carry a price (`{nombre, precio}`).
enum Catalogo {
    static let categorias = ["iPhone", "Celulares", "Pantallas", "Bicis", "Motos", "Accesorios"]
    static let conMarca: Set<String> = ["Celulares", "Pantallas"]

    /// Word put before brand and model in the "[producto]" text.
    static let etiquetas = ["iPhone": "iPhone", "Celulares": "Celular", "Pantallas": "Pantalla", "Bicis": "Bici", "Motos": "Moto", "Accesorios": ""]

    struct Datos: Equatable {
        var planos: [String: [JSON]] = [:]
        var marcas: [String: [String: [String]]] = [:]
    }

    static func leer(_ valor: JSON?) -> Datos {
        var datos = Datos()
        let objeto = valor?.object ?? [:]
        for categoria in categorias {
            if conMarca.contains(categoria) {
                var porMarca: [String: [String]] = [:]
                // Older flat lists (before brands) are ignored: the catalogue is captured again.
                for (marca, modelos) in objeto[categoria]?.object ?? [:] {
                    guard let lista = modelos.list else { continue }
                    porMarca[marca] = lista.compactMap { $0["nombre"]?.text ?? $0.text }
                }
                datos.marcas[categoria] = porMarca
            } else {
                datos.planos[categoria] = objeto[categoria]?.list ?? []
            }
        }
        return datos
    }

    /// "Celular Samsung Galaxy A15", "iPhone 15 Pro", "Moto Italika FT150".
    static func descripcion(categoria: String, marca: String = "", modelo: String) -> String {
        var partes: [String] = []
        let etiqueta = etiquetas[categoria] ?? categoria
        let resto = [marca, modelo].filter { !$0.isEmpty }.joined(separator: " ")
        if !etiqueta.isEmpty, !resto.lowercased().hasPrefix(etiqueta.lowercased()) { partes.append(etiqueta) }
        if !resto.isEmpty { partes.append(resto) }
        return partes.joined(separator: " ")
    }
}
