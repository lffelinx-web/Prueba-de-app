import XCTest
@testable import CentroDeDatos

final class PagosTests: XCTestCase {
    private func activo(compradoHaceDias dias: Int, semanas: Int = 13, extra: [String: JSON] = [:]) -> Cliente {
        var raw: [String: JSON] = [
            "id": "1",
            "nombre": "Ana",
            "categoria": "activos",
            "fechaCompra": .string(Fecha.iso(Fecha.sumar(dias: -dias, a: Fecha.hoy))),
            "semanas": .string(String(semanas)),
            "pagosConfirmados": .array([]),
        ]
        raw.merge(extra) { $1 }
        return Cliente(raw: raw).normalizado()
    }

    func testPrimerPagoHoy() {
        let c = activo(compradoHaceDias: 7)
        XCTAssertEqual(c.pagoPendienteHoy()?.num, 1)
        XCTAssertNil(c.pagoAtrasado())
        XCTAssertTrue(c.pagaHoy)
    }

    func testPagoAtrasado() {
        let c = activo(compradoHaceDias: 10)
        XCTAssertNil(c.pagoPendienteHoy())
        XCTAssertEqual(c.pagoAtrasado()?.num, 1)
    }

    func testConfirmadoAvanzaAlSiguiente() {
        let c = activo(compradoHaceDias: 14, extra: ["pagosConfirmados": .array([1])])
        XCTAssertEqual(c.pagoPendienteHoy()?.num, 2)
    }

    func testNoPagadoSeArrastraAlDiaDelSiguiente() {
        let c = activo(compradoHaceDias: 14, extra: ["pagosMarcadosNoPagado": .array([1])])
        XCTAssertEqual(c.pagoPendienteHoy()?.num, 1)
        XCTAssertTrue(c.pagoHoyConAtraso)
        XCTAssertNil(c.pagoAtrasado())
    }

    func testNoPagadoDescansaHastaElSiguiente() {
        let c = activo(compradoHaceDias: 10, extra: ["pagosMarcadosNoPagado": .array([1])])
        XCTAssertNil(c.pagoPendienteHoy())
        XCTAssertNil(c.pagoAtrasado())
    }

    func testSinPagosDespuesDeLaQuintaSemana() {
        let c = activo(compradoHaceDias: 40)
        XCTAssertNil(c.pagoActual())
    }

    func testFechaFinYSemanasRestantes() {
        let c = activo(compradoHaceDias: 70, semanas: 13)
        XCTAssertEqual(c.fechaFin.map(Fecha.iso), Fecha.iso(Fecha.sumar(dias: 21, a: Fecha.hoy)))
        XCTAssertEqual(c.semanasRestantes, 3)
    }
}

final class DiferenciasTests: XCTestCase {
    func testCambiosConRevision() {
        let base: [String: [String: JSON]] = [
            "a": ["id": "a", "nombre": "Uno", "_rev": 2],
            "c": ["id": "c", "nombre": "Tres"],
        ]
        let diff = Diferencias(tabla: "ca_clientes", base: base, claves: ["a": "0", "c": "c"], revisiones: ["a": 2, "c": 0])
        let (cambios, updates) = diff.calcular([
            ["id": "a", "nombre": "Uno editado", "_rev": 2],
            ["id": "b", "nombre": "Dos"],
        ])

        XCTAssertEqual(cambios.count, 3)
        XCTAssertEqual(updates["ca_clientes/0/nombre"] as? String, "Uno editado")
        XCTAssertEqual(updates["ca_clientes/0/_rev"] as? Int, 3)
        XCTAssertTrue(updates["ca_clientes/c"] is NSNull)
        let nuevo = updates["ca_clientes/b"] as? [String: Any]
        XCTAssertEqual(nuevo?["_rev"] as? Int64, 1)
        XCTAssertEqual(nuevo?["nombre"] as? String, "Dos")
    }

    func testSinCambiosNoEscribe() {
        let fila: [String: JSON] = ["id": "a", "pagosConfirmados": .array([1, 2])]
        let diff = Diferencias(tabla: "ca_clientes", base: ["a": fila], claves: [:], revisiones: [:])
        XCTAssertTrue(diff.calcular([fila]).updates.isEmpty)
    }

    func testEnviosPorSubclave() {
        let antes: [String: JSON] = ["id": "a", "ultimoEnvioRec": .object(["x": 1, "y": 2])]
        var despues = antes
        despues["ultimoEnvioRec"] = .object(["x": 1, "z": 3])
        let diff = Diferencias(tabla: "ca_clientes", base: ["a": antes], claves: [:], revisiones: [:])
        let updates = diff.calcular([despues]).updates
        XCTAssertTrue(updates["ca_clientes/a/ultimoEnvioRec/y"] is NSNull)
        XCTAssertEqual(updates["ca_clientes/a/ultimoEnvioRec/z"] as? Int64, 3)
        XCTAssertNil(updates["ca_clientes/a/ultimoEnvioRec/x"])
        XCTAssertEqual(updates["ca_clientes/a/_rev"] as? Int, 1)
    }

    func testCamposDesconocidosSeConservan() {
        var c = Cliente(raw: ["id": "a", "nombre": "Ana", "campoNuevoDeLaWeb": "valor"])
        c.nombre = "Ana María"
        XCTAssertEqual(c["campoNuevoDeLaWeb"], "valor")
    }
}

@MainActor
final class ReglasTests: XCTestCase {
    func testNormalizarNombre() {
        XCTAssertEqual(normalizarNombre("  María  José PÉREZ "), "maria jose perez")
    }

    func testPRAprobadaVencePasaAProspecto() {
        let pr = Cliente(raw: [
            "id": "p",
            "nombre": "Luis",
            "categoria": "pr-aprobadas",
            "fechaSolicitud": .string(Fecha.iso(Fecha.sumar(dias: -31, a: Fecha.hoy))),
        ])
        let (clientes, avisos) = Reglas.mantenimiento([pr])
        XCTAssertEqual(clientes.first?.categoria, .prospectos)
        XCTAssertTrue(clientes.first?.esPRAprobada ?? false)
        XCTAssertEqual(avisos.first?.tipo, "pr_a_prospecto")
    }

    func testCreditoVencidoPideConfirmacion() {
        let c = Cliente(raw: [
            "id": "v",
            "nombre": "Rosa",
            "categoria": "activos",
            "fechaCompra": .string(Fecha.iso(Fecha.sumar(dias: -100, a: Fecha.hoy))),
            "semanas": "13",
        ])
        let (clientes, avisos) = Reglas.mantenimiento([c])
        XCTAssertEqual(clientes.first?.categoria, .activos)
        XCTAssertEqual(avisos.first?.tipo, "vencido_a_sinrenovar")
    }

    func testDobleFinanciamientoVencidoSeArchiva() {
        let viejo = Cliente(raw: [
            "id": "viejo", "nombre": "Rosa", "categoria": "activos", "dobleFinId": "nuevo",
            "fechaCompra": .string(Fecha.iso(Fecha.sumar(dias: -100, a: Fecha.hoy))), "semanas": "13",
        ])
        let nuevo = Cliente(raw: [
            "id": "nuevo", "nombre": "Rosa", "categoria": "activos", "dobleFinId": "viejo",
            "fechaCompra": .string(Fecha.iso(Fecha.sumar(dias: -10, a: Fecha.hoy))), "semanas": "13",
        ])
        let (clientes, avisos) = Reglas.mantenimiento([viejo, nuevo])
        XCTAssertEqual(clientes.map(\.id), ["nuevo"])
        XCTAssertNil(clientes.first?.dobleFinId)
        XCTAssertEqual(clientes.first?.historial.count, 1)
        XCTAssertTrue(avisos.isEmpty)
    }

    func testReferenciasSincronizadas() {
        var lista = [
            Cliente(raw: ["id": "t", "nombre": "Titular", "categoria": "activos"]),
            Cliente(raw: ["id": "r1", "nombre": "Vieja", "tel": "1111111111", "categoria": "prospectos", "refDeId": "t"]),
            Cliente(raw: ["id": "r2", "nombre": "Sobra", "tel": "2222222222", "categoria": "prospectos", "refDeId": "t"]),
        ]
        AltaActivo.sincronizarReferencias(de: "t", refs: [Referencia(nombre: "Nueva", tel: "3333333333")], titular: "Titular", asesor: "Luis", en: &lista)
        XCTAssertEqual(lista.map(\.id), ["t", "r1"])
        XCTAssertEqual(lista[1].nombre, "Nueva")
        XCTAssertEqual(lista[1].tel, "3333333333")
    }

    func testDuplicadosEnProspectos() {
        let lista = [
            Cliente(raw: ["id": "a", "nombre": "Ana", "tel": "1", "categoria": "prospectos"]),
            Cliente(raw: ["id": "b", "nombre": " ana ", "tel": "2", "categoria": "prospectos"]),
            Cliente(raw: ["id": "c", "nombre": "Otra", "tel": "2", "categoria": "prospectos", "inhabilitado": true]),
        ]
        let pares = Reglas.duplicados(.prospectos, en: lista)
        XCTAssertEqual(pares.count, 1)
        XCTAssertTrue(pares[0].mismoNombre)
    }
}

final class MensajesTests: XCTestCase {
    func testNombreYApellido() {
        XCTAssertEqual(Mensajes.primerNombreApellido("DELIA GARRIDO HERNANDEZ"), "Delia Garrido")
        let partes = Mensajes.partirNombre("MARIA DE JESUS LOPEZ PEREZ")
        XCTAssertEqual(partes.nombre, "Maria de Jesus")
        XCTAssertEqual(partes.apellido, "Lopez")
        XCTAssertEqual(Mensajes.primerNombreApellido("JUAN DE LA CRUZ"), "Juan de la Cruz")
    }

    func testRecordatorioDePago() {
        var plantilla = PlantillaRecordatorio()
        plantilla.saludo = "Hola, "
        plantilla.lugar = "te escribimos de Macropréstamos."
        plantilla.cuerpo = "Tu [NUMERO DE PAGO] pago vence hoy"
        let cliente = Cliente(raw: ["id": "1", "nombre": "DELIA GARRIDO HERNANDEZ"])
        let texto = Mensajes.recordatorio(plantilla, tipo: .pagosHoy, cliente: cliente, extras: ExtrasMensaje(numPago: "2°"))
        XCTAssertEqual(texto, "Hola, *Delia Garrido*\n\nte escribimos de Macropréstamos.\n\nTu 2° pago vence hoy")
    }

    func testSinMacropesosSeQuitaLaLinea() {
        var plantilla = MensajePredeterminado()
        plantilla.cuerpo = "Promoción especial\nTienes [macropesos] disponibles"
        let cliente = Cliente(raw: ["id": "1", "nombre": "Ana Ruiz"])
        let texto = Mensajes.predeterminado(plantilla, cliente: cliente, cuerpo: .promociones)
        XCTAssertEqual(texto, "*Ana Ruiz*\n\nPromoción especial")
    }

    func testArticuloSegunProducto() {
        var plantilla = MensajePredeterminado()
        plantilla.advCreditos = true
        plantilla.cuerpoCreditosAdv = "Llévate el [tipo de producto] [modelo] con [enganche]"
        let cliente = Cliente(raw: ["id": "1", "nombre": "Ana Ruiz"])
        let extras = ExtrasMensaje(lineaCredito: "8000", enganche: "1500", tipoProducto: "Pantallas", modelo: "TV 50")
        let texto = Mensajes.predeterminado(plantilla, cliente: cliente, cuerpo: .creditos, extras: extras)
        XCTAssertTrue(texto.hasSuffix("Llévate la pantalla TV 50 con $1,500.00"), texto)
    }
}

final class EnviosTests: XCTestCase {
    func testContactadoRecienteQuedaBloqueado() {
        let ahora = Double(Fecha.milisegundos())
        let lista = [
            Cliente(raw: ["id": "a", "nombre": "Ana", "tel": "1111111111", "categoria": "prospectos", "tieneWA": true, "ultimoEnvioMasivo": .number(ahora)]),
            Cliente(raw: ["id": "b", "nombre": "Beto", "tel": "2222222222", "categoria": "prospectos", "tieneWA": true]),
            Cliente(raw: ["id": "c", "nombre": "Beto otra vez", "tel": "2222222222", "categoria": "prospectos", "tieneWA": true]),
        ]
        let resultado = Envios.lista(.prospectos, cuerpo: .promociones, en: lista, dias: Envios.DiasBloqueo())
        XCTAssertEqual(resultado.contactos.map(\.id), ["b"])
        XCTAssertEqual(resultado.bloqueados, 1)
        XCTAssertEqual(Envios.bloqueados(.prospectos, en: lista, dias: Envios.DiasBloqueo()).map(\.id), ["a"])
    }

    func testPagosDelDia() {
        let c = Cliente(raw: [
            "id": "1", "nombre": "Ana", "categoria": "activos", "semanas": "13",
            "fechaCompra": .string(Fecha.iso(Fecha.sumar(dias: -14, a: Fecha.hoy))),
        ]).normalizado()
        XCTAssertEqual(Envios.pagos(enDia: 0, de: [c]).first?.numero, 2)
        XCTAssertTrue(Envios.pagos(enDia: 1, de: [c]).isEmpty)
    }

    func testCsvConPrimerNombre() {
        let c = Cliente(raw: ["id": "1", "nombre": "MARIA DE JESUS LOPEZ", "tel": "5512345678"])
        XCTAssertEqual(Envios.csv([c]), "\u{FEFF}\"Name\",\"Phone\"\n\"Maria de Jesus\",\"5512345678\"")
    }
}

final class ExcelTests: XCTestCase {
    func testCRC32() {
        XCTAssertEqual(Zip.crc32(Data("123456789".utf8)), 0xCBF43926)
    }

    func testLibroEsZipConDosHojas() {
        let clientes = [
            Cliente(raw: ["id": "1", "nombre": "Ana & Cía", "categoria": "activos", "fechaCompra": "2026-10-01", "semanas": "13",
                          "refs": .array([.object(["nombre": "Beto", "tel": "5512345678"])])]),
            Cliente(raw: ["id": "2", "nombre": "Carla", "categoria": "sinrenovar"]),
        ]
        let datos = Excel.baseDeDatos(clientes)
        XCTAssertEqual(Array(datos.prefix(4)), [0x50, 0x4B, 0x03, 0x04])
        let texto = String(decoding: datos, as: UTF8.self)
        XCTAssertTrue(texto.contains("<sheet name=\"Clientes activos\""))
        XCTAssertTrue(texto.contains("<sheet name=\"Sin renovar\""))
        XCTAssertTrue(texto.contains("Ana &amp; Cía"))
        XCTAssertTrue(texto.contains("  Ref. 1: Beto"))
    }
}
