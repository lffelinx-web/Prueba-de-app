import Foundation

/// A minimal .xlsx writer: inline strings, a few cell styles and fixed column widths,
/// packed in an uncompressed zip. Enough for the web app's database export.
enum Excel {
    enum Estilo: Int {
        case normal = 0, encabezado, referencia, sinReferencia, cliente
    }

    struct Hoja {
        var nombre: String
        var anchos: [Double]
        var filas: [(celdas: [String], estilo: Estilo)]
    }

    static func libro(_ hojas: [Hoja]) -> Data {
        var archivos: [(String, Data)] = []
        let tiposHojas = hojas.indices.map {
            "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined()
        archivos.append(("[Content_Types].xml", xml("""
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\(tiposHojas)</Types>
        """)))
        archivos.append(("_rels/.rels", xml("""
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
        """)))
        let listaHojas = hojas.enumerated().map {
            "<sheet name=\"\(escapar(String($1.nombre.prefix(31))))\" sheetId=\"\($0 + 1)\" r:id=\"rId\($0 + 1)\"/>"
        }.joined()
        archivos.append(("xl/workbook.xml", xml("""
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>\(listaHojas)</sheets></workbook>
        """)))
        let relaciones = hojas.indices.map {
            "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>"
        }.joined()
        archivos.append(("xl/_rels/workbook.xml.rels", xml("""
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(relaciones)<Relationship Id="rId\(hojas.count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
        """)))
        archivos.append(("xl/styles.xml", xml(estilos)))
        for (n, hoja) in hojas.enumerated() {
            archivos.append(("xl/worksheets/sheet\(n + 1).xml", xml(hojaXML(hoja))))
        }
        return Zip.empaquetar(archivos)
    }

    private static let estilos = """
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <fonts count="4"><font><sz val="11"/><name val="Arial"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>\
    <font><i/><sz val="10"/><color rgb="FF555555"/><name val="Arial"/></font><font><i/><sz val="10"/><color rgb="FFAAAAAA"/><name val="Arial"/></font></fonts>\
    <fills count="5"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FF1A3A6B"/></patternFill></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFF0F4FF"/></patternFill></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFEFF4FB"/></patternFill></fill></fills>\
    <borders count="1"><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs>\
    <cellXfs count="5"><xf/>\
    <xf fontId="1" fillId="2" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>\
    <xf fontId="2" fillId="3" applyFont="1" applyFill="1"/>\
    <xf fontId="3" applyFont="1"/>\
    <xf fontId="0" fillId="4" applyFill="1"/></cellXfs></styleSheet>
    """

    private static func hojaXML(_ hoja: Hoja) -> String {
        let columnas = hoja.anchos.enumerated().map {
            "<col min=\"\($0 + 1)\" max=\"\($0 + 1)\" width=\"\($1)\" customWidth=\"1\"/>"
        }.joined()
        var filas = ""
        for (n, fila) in hoja.filas.enumerated() {
            let r = n + 1
            filas += "<row r=\"\(r)\"\(r == 1 ? " ht=\"20\" customHeight=\"1\"" : "")>"
            for (c, valor) in fila.celdas.enumerated() {
                let referencia = columna(c) + String(r)
                let estilo = fila.estilo == .normal ? "" : " s=\"\(fila.estilo.rawValue)\""
                filas += "<c r=\"\(referencia)\" t=\"inlineStr\"\(estilo)><is><t xml:space=\"preserve\">\(escapar(valor))</t></is></c>"
            }
            filas += "</row>"
        }
        return "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><cols>\(columnas)</cols><sheetData>\(filas)</sheetData></worksheet>"
    }

    private static func columna(_ indice: Int) -> String {
        var n = indice + 1, letras = ""
        while n > 0 {
            let resto = (n - 1) % 26
            letras = String(UnicodeScalar(65 + resto)!) + letras
            n = (n - 1) / 26
        }
        return letras
    }

    private static func xml(_ cuerpo: String) -> Data {
        Data(("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n" + cuerpo).utf8)
    }

    static func escapar(_ texto: String) -> String {
        texto.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - The web app's export

    /// "Clientes activos" and "Sin renovar", each client followed by its references, oldest purchase first.
    static func baseDeDatos(_ clientes: [Cliente]) -> Data {
        func hoja(_ categoria: Categoria, _ nombre: String) -> Hoja {
            let encabezado = ["Fecha de compra", "Nombre completo", "Teléfono", "SL", "Tipo", "Plazo (semanas)", "Asesor", "Fecha de finalización"]
            var filas: [(celdas: [String], estilo: Estilo)] = [(encabezado, .encabezado)]
            let lista = clientes.filter { $0.categoria == categoria && !$0.inhabilitado }
                .sorted { ($0.fechaCompra ?? "") < ($1.fechaCompra ?? "") }
            for c in lista {
                filas.append(([
                    Fecha.corta(c.fechaCompra), c.nombre.isEmpty ? "—" : c.nombre, c.tel.isEmpty ? "—" : c.tel, c.sl ?? "—",
                    c.tipo ?? "Compra", c.semanas.map { "\($0) sem." } ?? "—", c.asesor ?? "—", Fecha.corta(c.fechaFin),
                ], .cliente))
                if c.refs.isEmpty {
                    filas.append((["", "  (Sin referencias)", "", "", "", "", "", ""], .sinReferencia))
                } else {
                    for (n, ref) in c.refs.enumerated() {
                        filas.append((["", "  Ref. \(n + 1): \(ref.nombre.isEmpty ? "—" : ref.nombre)", ref.tel, "", "", "", "", ""], .referencia))
                    }
                }
                filas.append((Array(repeating: "", count: 8), .normal))
            }
            return Hoja(nombre: nombre, anchos: [14, 34, 13, 20, 12, 14, 14, 16], filas: filas)
        }
        return libro([hoja(.activos, "Clientes activos"), hoja(.sinrenovar, "Sin renovar")])
    }
}

/// Stored (uncompressed) zip archive.
enum Zip {
    private static let tablaCRC: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ datos: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in datos { c = tablaCRC[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    static func empaquetar(_ archivos: [(String, Data)]) -> Data {
        var salida = Data()
        var central = Data()
        for (nombre, datos) in archivos {
            let nombreDatos = Data(nombre.utf8)
            let crc = crc32(datos)
            let desplazamiento = UInt32(salida.count)
            salida.u32(0x04034b50); salida.u16(20); salida.u16(0x0800); salida.u16(0)
            salida.u16(0); salida.u16(0x21)
            salida.u32(crc); salida.u32(UInt32(datos.count)); salida.u32(UInt32(datos.count))
            salida.u16(UInt16(nombreDatos.count)); salida.u16(0)
            salida.append(nombreDatos); salida.append(datos)

            central.u32(0x02014b50); central.u16(20); central.u16(20); central.u16(0x0800); central.u16(0)
            central.u16(0); central.u16(0x21)
            central.u32(crc); central.u32(UInt32(datos.count)); central.u32(UInt32(datos.count))
            central.u16(UInt16(nombreDatos.count)); central.u16(0); central.u16(0); central.u16(0); central.u16(0)
            central.u32(0); central.u32(desplazamiento)
            central.append(nombreDatos)
        }
        let inicioCentral = UInt32(salida.count)
        salida.append(central)
        salida.u32(0x06054b50); salida.u16(0); salida.u16(0)
        salida.u16(UInt16(archivos.count)); salida.u16(UInt16(archivos.count))
        salida.u32(UInt32(central.count)); salida.u32(inicioCentral); salida.u16(0)
        return salida
    }
}

private extension Data {
    mutating func u16(_ valor: UInt16) { Swift.withUnsafeBytes(of: valor.littleEndian) { append(contentsOf: $0) } }
    mutating func u32(_ valor: UInt32) { Swift.withUnsafeBytes(of: valor.littleEndian) { append(contentsOf: $0) } }
}
