import Foundation

/// Turns an edited copy of a collection into the multi-location update the database rules accept,
/// exactly like the web app's `_secureDiff` + `save`: changed fields only, plus a bumped `_rev`
/// on every touched record so a concurrent edit by someone else is rejected as a whole.
struct Diferencias {
    enum Accion: String { case create, update, delete }

    struct Cambio {
        let id: String
        let accion: Accion
        let campos: [String]
    }

    /// Fields whose children are written one by one so two people can stamp different keys.
    private static let porSubclave: Set<String> = ["ultimoEnvioRec", "ultimoEnvioSinRenovar"]

    let tabla: String
    let base: [String: [String: JSON]]   // id → record as last read
    let claves: [String: String]         // id → key under the table
    let revisiones: [String: Int]        // id → `_rev` as last read

    func calcular(_ filas: [[String: JSON]]) -> (cambios: [Cambio], updates: [String: Any]) {
        var despues: [String: [String: JSON]] = [:]
        for fila in filas {
            guard let id = fila["id"]?.text else { continue }
            despues[id] = fila
        }

        var cambios: [Cambio] = []
        var updates: [String: Any] = [:]
        let ids = Set(base.keys).union(despues.keys).sorted()
        for id in ids {
            let ruta = tabla + "/" + (claves[id] ?? id)
            switch (base[id], despues[id]) {
            case (nil, let nuevo?):
                var valor = nuevo
                valor["_rev"] = 1
                updates[ruta] = JSON.object(valor).firebaseValue
                cambios.append(Cambio(id: id, accion: .create, campos: []))
            case (_?, nil):
                updates[ruta] = NSNull()
                cambios.append(Cambio(id: id, accion: .delete, campos: []))
            case (let antes?, let ahora?):
                var campos: [String] = []
                for campo in Set(antes.keys).union(ahora.keys).sorted() where campo != "_rev" {
                    let viejo = antes[campo] ?? .null, nuevo = ahora[campo] ?? .null
                    guard viejo != nuevo else { continue }
                    campos.append(campo)
                    if Diferencias.porSubclave.contains(campo) {
                        let subViejo = viejo.object ?? [:], subNuevo = nuevo.object ?? [:]
                        for sub in Set(subViejo.keys).union(subNuevo.keys) where subViejo[sub] != subNuevo[sub] {
                            updates[ruta + "/" + campo + "/" + sub] = (subNuevo[sub] ?? .null).firebaseValue
                        }
                    } else {
                        updates[ruta + "/" + campo] = nuevo.firebaseValue
                    }
                }
                guard !campos.isEmpty else { continue }
                updates[ruta + "/_rev"] = (revisiones[id] ?? 0) + 1
                cambios.append(Cambio(id: id, accion: .update, campos: campos))
            case (nil, nil):
                break
            }
        }
        return (cambios, updates)
    }
}
