import SwiftUI
import UIKit

struct MenuMensajesView: View {
    let masivos: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(masivos ? CategoriaMensaje.masivos : CategoriaMensaje.personalizados) { categoria in
                    NavigationLink(value: destino(categoria)) {
                        OpcionMenu(titulo: categoria.titulo, detalle: categoria.descripcion, icono: categoria.icono, color: color(categoria))
                    }
                }
            }
            .buttonStyle(.plain)
            .padding()
        }
        .background(Tema.fondo)
        .navigationTitle(masivos ? "Mensajes masivos" : "Mensajes personalizados")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func destino(_ categoria: CategoriaMensaje) -> RutaHerramienta {
        if !masivos, categoria == .sinrenovar { return .subtiposSinRenovar }
        return .envio(masivos: masivos, categoria: categoria, cuerpo: nil)
    }

    private func color(_ categoria: CategoriaMensaje) -> Color {
        switch categoria {
        case .sinrenovar: return Tema.morado
        case .porfinalizar: return Tema.advertencia
        case .prAprobadas: return Tema.exito
        case .prospectos, .prospectosVerificados: return Tema.info
        }
    }
}

struct MenuSubtiposSinRenovarView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("¿Qué tipo de mensaje vas a enviar?").font(.subheadline).foregroundStyle(Tema.apagado)
                opcion(.promociones, "Promociones", "Mensaje promocional general", "megaphone.fill", Tema.advertencia)
                opcion(.macropesos, "Macropesos", "Cliente por cliente con sus macropesos", "banknote", Tema.acento)
                opcion(.linea, "Línea de crédito", "Captura el monto manual por cliente", "chart.bar.fill", Tema.exito)
            }
            .buttonStyle(.plain)
            .padding()
        }
        .background(Tema.fondo)
        .navigationTitle("Personalizados — Sin renovar")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func opcion(_ cuerpo: CuerpoMensaje, _ titulo: String, _ detalle: String, _ icono: String, _ color: Color) -> some View {
        NavigationLink(value: RutaHerramienta.envio(masivos: false, categoria: .sinrenovar, cuerpo: cuerpo)) {
            OpcionMenu(titulo: titulo, detalle: detalle, icono: icono, color: color)
        }
    }
}

/// A sending list: checkboxes, copy and CSV for mass messages; one WhatsApp per contact for
/// personalized ones. Contacts marked as sent leave the list and stay blocked for the category's days.
struct ListaEnvioView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openURL) private var openURL
    let masivos: Bool
    let categoria: CategoriaMensaje
    let cuerpo: CuerpoMensaje?

    @AppStorage("ca_masivos_por_pagina") private var porPagina = 50
    @State private var ids: [String] = []
    @State private var bloqueados = 0
    @State private var cargado = false
    @State private var pagina = 0
    @State private var busqueda = ""
    @State private var deseleccionados: Set<String> = []
    @State private var lineaAvanzada = false
    @State private var lineas: [String: String] = [:]
    @State private var enganches: [String: String] = [:]
    @State private var equipos: [String: String] = [:]
    @State private var tiposProducto: [String: String] = [:]
    @State private var modelos: [String: String] = [:]
    @State private var confirmacion: Confirmacion?
    @State private var verBloqueados = false
    @State private var archivo: URL?

    private var cuerpoEnvio: CuerpoMensaje { cuerpo ?? .promociones }

    private var titulo: String {
        let tipo = masivos ? "Masivos" : "Personalizados"
        let sub: String
        switch cuerpo {
        case .macropesos?: sub = " · Macropesos"
        case .linea?: sub = " · Línea de crédito"
        case .promociones?: sub = " · Promociones"
        default: sub = ""
        }
        return "\(tipo) — \(categoria.titulo)\(sub)"
    }

    var body: some View {
        let visibles = contactosVisibles
        let inicio = min(pagina * porPagina, visibles.count)
        let enPagina = Array(visibles[inicio..<min(inicio + porPagina, visibles.count)])
        let plantilla = store.mensajePredeterminado(categoria)

        List {
            encabezado(total: visibles.count, inicio: inicio, enPagina: enPagina, plantilla: plantilla)
                .seccionTema()

            if enPagina.isEmpty {
                Text(busqueda.isEmpty ? "Sin registros disponibles en esta categoría" : "Sin coincidencias para \"\(busqueda)\"")
                    .foregroundStyle(Tema.apagado)
                    .frame(maxWidth: .infinity)
                    .filaTarjeta()
            } else if masivos {
                seleccionMasivos(enPagina)
                accionesMasivos(enPagina: enPagina, quedanMas: inicio + porPagina < visibles.count)
            } else {
                ForEach(enPagina) { c in
                    filaPersonalizada(c, plantilla: plantilla)
                        .tarjeta()
                        .filaTarjeta()
                }
                if inicio + porPagina < visibles.count {
                    Button("Siguiente \(porPagina) →") { pagina += 1 }
                        .buttonStyle(.pastilla(Tema.acento, relleno: true))
                        .frame(maxWidth: .infinity)
                        .filaTarjeta()
                }
            }

            if bloqueados > 0 {
                Button("👁 Ver \(bloqueados) contacto\(bloqueados == 1 ? "" : "s") bloqueado\(bloqueados == 1 ? "" : "s")") { verBloqueados = true }
                    .buttonStyle(.pastilla())
                    .frame(maxWidth: .infinity)
                    .filaTarjeta()
            }
        }
        .listStyle(.plain)
        .fondoTema()
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
        .modifier(BuscadorOpcional(activo: masivos && categoria == .prospectos, texto: $busqueda))
        .onChange(of: busqueda) { _, _ in pagina = 0 }
        .onAppear { if !cargado { recargar() } }
        .confirmacion($confirmacion)
        .sheet(isPresented: $verBloqueados, onDismiss: recargar) {
            BloqueadosMensajeView(categoria: categoria)
        }
        .sheet(item: Binding(get: { archivo.map(ArchivoCompartido.init) }, set: { archivo = $0?.url })) { item in
            HojaCompartir(elementos: [item.url])
        }
    }

    // MARK: Mass selection

    private func todosSeleccionados(_ enPagina: [Cliente]) -> Binding<Bool> {
        Binding(
            get: { enPagina.allSatisfy { !deseleccionados.contains($0.id) } },
            set: { todos in
                for c in enPagina {
                    if todos { deseleccionados.remove(c.id) } else { deseleccionados.insert(c.id) }
                }
            }
        )
    }

    private func alternar(_ id: String) {
        if deseleccionados.contains(id) { deseleccionados.remove(id) } else { deseleccionados.insert(id) }
    }

    private func filaMasiva(_ c: Cliente) -> some View {
        let elegido = !deseleccionados.contains(c.id)
        return Button {
            alternar(c.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: elegido ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(elegido ? Tema.acento : Tema.apagado)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.tel).font(Tipo.numero.weight(.medium)).foregroundStyle(Tema.texto)
                    Text(c.nombre).font(Tipo.detalle).foregroundStyle(Tema.apagado).lineLimit(1)
                }
            }
        }
    }

    private func seleccionMasivos(_ enPagina: [Cliente]) -> some View {
        let elegidos = enPagina.filter { !deseleccionados.contains($0.id) }.count
        return Section {
            Toggle(isOn: todosSeleccionados(enPagina)) {
                Text("Seleccionar todos").font(.subheadline)
                Text("\(elegidos)/\(enPagina.count)").font(.caption).foregroundStyle(Tema.acento)
            }
            ForEach(enPagina) { c in filaMasiva(c) }
        }
        .seccionTema()
    }

    // MARK: Data

    private var contactosVisibles: [Cliente] {
        let porId = Dictionary(store.clientes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var lista = ids.compactMap { porId[$0] }.filter { $0.tieneWA && !$0.tel.isEmpty && !$0.suspendido }
        let q = busqueda.lowercased().trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { lista = lista.filter { $0.nombre.lowercased().contains(q) || $0.tel.lowercased().contains(q) } }
        return lista
    }

    private func recargar() {
        let resultado = Envios.lista(categoria, cuerpo: cuerpoEnvio, en: store.clientes, dias: store.diasBloqueo)
        ids = resultado.contactos.map(\.id)
        bloqueados = resultado.bloqueados
        deseleccionados = []
        pagina = 0
        cargado = true
        for c in resultado.contactos {
            if let guardada = c["lineaCreditoGuardada"]?.text, lineas[c.id] == nil { lineas[c.id] = guardada }
        }
    }

    private func retirar(_ marcados: [String]) {
        let conjunto = Set(marcados)
        ids.removeAll { conjunto.contains($0) }
        bloqueados += marcados.count
        deseleccionados.subtract(conjunto)
        if pagina * porPagina >= contactosVisibles.count, pagina > 0 { pagina -= 1 }
    }

    // MARK: Header and mass actions

    @ViewBuilder
    private func encabezado(total: Int, inicio: Int, enPagina: [Cliente], plantilla: MensajePredeterminado?) -> some View {
        Section {
            if bloqueados > 0 {
                Text("📅 \(bloqueados) contacto\(bloqueados == 1 ? "" : "s") no aparece\(bloqueados == 1 ? "" : "n") porque recibió mensaje en los últimos \(store.diasBloqueo.dias(categoria.claveBloqueo)) días.")
                    .font(.caption)
                    .foregroundStyle(Tema.advertencia)
            }
            if !masivos, plantilla?.tieneContenido != true {
                Label("Configura primero la plantilla en Configuración → Plantillas.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Tema.advertencia)
            }
            if total > 0 {
                HStack {
                    Text("Mostrando \(inicio + 1)–\(inicio + enPagina.count) de \(total)").font(.caption).foregroundStyle(Tema.apagado)
                    Spacer()
                    Picker("Por página", selection: $porPagina) {
                        ForEach([10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 150, 200], id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .onChange(of: porPagina) { _, _ in pagina = 0 }
                }
            }
            if !masivos, categoria == .sinrenovar, cuerpo == .linea {
                Toggle("Opciones avanzadas (guardar líneas)", isOn: $lineaAvanzada).font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private func accionesMasivos(enPagina: [Cliente], quedanMas: Bool) -> some View {
        let seleccion = enPagina.filter { !deseleccionados.contains($0.id) }
        Section {
            HStack {
                Button("📋 Copiar completo") { copiar(seleccion, soloNumeros: false) }
                Spacer()
                Button("🔢 Solo números") { copiar(seleccion, soloNumeros: true) }
                Spacer()
                Button("📥 CSV") { exportar(seleccion) }
            }
            .buttonStyle(.pastilla())
            Button {
                confirmacion = Confirmacion(
                    titulo: "✓ Marcar como enviados",
                    mensaje: "¿Confirmar envío a los \(seleccion.count) contacto\(seleccion.count == 1 ? "" : "s") seleccionado\(seleccion.count == 1 ? "" : "s")? Quedarán bloqueados \(store.diasBloqueo.dias(categoria.claveBloqueo)) días.",
                    boton: "Marcar \(seleccion.count)"
                ) {
                    let marcados = seleccion.map(\.id)
                    if await store.marcarMensajeEnviado(marcados, categoria: categoria, cuerpo: cuerpoEnvio) {
                        retirar(marcados)
                        store.avisar("✓ \(marcados.count) contacto\(marcados.count == 1 ? "" : "s") marcado\(marcados.count == 1 ? "" : "s") como enviado\(marcados.count == 1 ? "" : "s")")
                    }
                }
            } label: {
                Text(seleccion.isEmpty ? "Selecciona al menos un contacto" : "✓ Marcar como enviados los \(seleccion.count) seleccionado\(seleccion.count == 1 ? "" : "s")")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pastilla(Tema.acento, relleno: true))
            .disabled(seleccion.isEmpty)
            if quedanMas {
                Button("Siguiente \(porPagina) →") { pagina += 1 }
                    .frame(maxWidth: .infinity)
            }
        }
        .seccionTema()
    }

    private func copiar(_ contactos: [Cliente], soloNumeros: Bool) {
        guard !contactos.isEmpty else { return store.avisar("Selecciona al menos un contacto", advertencia: true) }
        UIPasteboard.general.string = soloNumeros
            ? contactos.map(\.tel).joined(separator: "\n")
            : contactos.map { "\(Mensajes.primerNombreApellido($0.nombre))\t\($0.tel)" }.joined(separator: "\n")
        store.avisar(soloNumeros ? "✓ \(contactos.count) número\(contactos.count == 1 ? "" : "s") copiado\(contactos.count == 1 ? "" : "s")" : "✓ Lista copiada (\(contactos.count))")
    }

    private func exportar(_ contactos: [Cliente]) {
        guard !contactos.isEmpty else { return store.avisar("Selecciona al menos un contacto", advertencia: true) }
        let marca = Fecha.timestampISO().prefix(19).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(categoria.rawValue)_\(marca).csv")
        do {
            try Envios.csv(contactos).write(to: url, atomically: true, encoding: .utf8)
            archivo = url
        } catch {
            store.avisar("No se pudo exportar: \(error.localizedDescription)", advertencia: true)
        }
    }

    // MARK: Personalized rows

    private func cuerpoPara(_ c: Cliente) -> CuerpoMensaje {
        switch categoria {
        case .prAprobadas: return (c.tipocred ?? "").lowercased() == "financing" ? .financing : .creditos
        case .porfinalizar: return .porfinalizar
        default: return cuerpoEnvio
        }
    }

    private func avanzadasPR(_ c: Cliente, _ plantilla: MensajePredeterminado?) -> Bool {
        cuerpoPara(c) == .financing ? plantilla?.advFinancing == true : plantilla?.advCreditos == true
    }

    private func campo(_ titulo: String, _ mapa: Binding<[String: String]>, _ id: String) -> some View {
        TextField(titulo, text: Binding(get: { mapa.wrappedValue[id] ?? "" }, set: { mapa.wrappedValue[id] = $0 }))
            .keyboardType(.decimalPad)
            .campoTema()
    }

    @ViewBuilder
    private func filaPersonalizada(_ c: Cliente, plantilla: MensajePredeterminado?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    NombreCliente(nombre: c.nombre)
                    infoSecundaria(c)
                }
                Spacer()
                Button {
                    enviar(c, plantilla: plantilla)
                } label: {
                    Image(systemName: "message.fill")
                }
                .buttonStyle(.pastilla(Tema.whatsapp, relleno: true))
                Button {
                    confirmacion = Confirmacion(
                        titulo: "Marcar como enviado",
                        mensaje: "¿Marcar a \(c.nombre) como enviado? Quedará bloqueado \(store.diasBloqueo.dias(categoria.claveBloqueo)) días.",
                        boton: "Marcar"
                    ) {
                        if await store.marcarMensajeEnviado([c.id], categoria: categoria, cuerpo: cuerpoEnvio) {
                            retirar([c.id])
                            store.avisar("✓ Marcado como enviado")
                        }
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.pastilla())
            }
            camposExtra(c, plantilla: plantilla)
        }
    }

    @ViewBuilder
    private func infoSecundaria(_ c: Cliente) -> some View {
        switch (categoria, cuerpoPara(c)) {
        case (_, .macropesos):
            Text("💰 \(Dinero.texto(c.macropesos ?? 0))").font(Tipo.detalle.monospaced()).foregroundStyle(Tema.acento)
        case (_, .linea):
            Text(c.sl ?? "—").font(Tipo.detalle.monospaced()).foregroundStyle(Tema.acento)
        case (.prAprobadas, let tipo):
            Text("\(c.numPR ?? "—") · \(tipo == .financing ? "💼 Financing" : "💳 Créditos")").font(Tipo.detalle.monospaced()).foregroundStyle(Tema.acento)
        case (.porfinalizar, _):
            Text("\(c.sl ?? "—") · 💰 \(Dinero.texto(c.macropesos ?? 0))").font(Tipo.detalle.monospaced()).foregroundStyle(Tema.acento)
        default:
            Text(c.tel).font(Tipo.detalle.monospaced()).foregroundStyle(Tema.apagado)
        }
    }

    @ViewBuilder
    private func camposExtra(_ c: Cliente, plantilla: MensajePredeterminado?) -> some View {
        let tipo = cuerpoPara(c)
        if tipo == .linea {
            let guardada = c["lineaCreditoGuardada"]?.text
            HStack(spacing: 6) {
                campo(lineaAvanzada || guardada == nil ? "Monto $" : Dinero.texto(Double(guardada ?? "")), $lineas, c.id)
                if lineaAvanzada {
                    if let guardada { Text(Dinero.texto(Double(guardada))).font(.caption.weight(.semibold)).foregroundStyle(Tema.exito) }
                    if store.esAdmin {
                        Button { guardarLinea(c) } label: { Image(systemName: guardada == nil ? "square.and.arrow.down" : "pencil") }
                            .buttonStyle(.pastilla())
                    }
                }
            }
        } else if tipo == .porfinalizar || ((tipo == .financing || tipo == .creditos) && !avanzadasPR(c, plantilla)) {
            campo("Línea de crédito $", $lineas, c.id)
        } else if tipo == .financing || tipo == .creditos {
            HStack(spacing: 6) {
                campo("Línea $", $lineas, c.id)
                campo("Enganche $", $enganches, c.id)
            }
            if tipo == .financing {
                Picker("Equipo", selection: Binding(get: { equipos[c.id] ?? "" }, set: { equipos[c.id] = $0 })) {
                    Text("Equipo").tag("")
                    ForEach(store.catalogoCelulares.keys.sorted(), id: \.self) { marca in
                        Section(marca) {
                            ForEach(store.catalogoCelulares[marca] ?? [], id: \.self) { modelo in
                                Text(modelo).tag(marca + " " + modelo)
                            }
                        }
                    }
                }
                .font(.caption)
            } else {
                HStack {
                    Picker("Tipo prod.", selection: Binding(get: { tiposProducto[c.id] ?? "" }, set: { tiposProducto[c.id] = $0; modelos[c.id] = "" })) {
                        Text("Tipo prod.").tag("")
                        ForEach(Store.categoriasProducto, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Modelo", selection: Binding(get: { modelos[c.id] ?? "" }, set: { modelos[c.id] = $0 })) {
                        Text("Modelo").tag("")
                        ForEach(store.modelos(de: tiposProducto[c.id] ?? ""), id: \.self) { Text($0).tag($0) }
                    }
                }
                .font(.caption)
            }
        }
    }

    private func guardarLinea(_ c: Cliente) {
        let texto = (lineas[c.id] ?? "").trimmingCharacters(in: .whitespaces)
        guard let monto = Double(texto), monto >= 0 else { return store.avisar("Captura un monto válido (0 para suspender)", advertencia: true) }
        if monto == 0 {
            confirmacion = Confirmacion(
                titulo: "⛔ Suspender cliente",
                mensaje: "¿Suspender a \(c.nombre) por 21 días en línea de crédito sin renovar? No aparecerá en esta lista hasta que se cumpla el plazo.",
                boton: "Suspender 21 días",
                destructivo: true
            ) {
                if await store.suspenderLinea(c.id) {
                    lineas[c.id] = nil
                    retirar([c.id])
                    bloqueados -= 1
                    store.avisar("⛔ Cliente suspendido 21 días")
                }
            }
        } else {
            Task {
                if await store.guardarLinea(c.id, monto: texto) {
                    store.avisar("💾 Línea guardada: \(Dinero.texto(monto))")
                }
            }
        }
    }

    private func monto(_ mapa: [String: String], _ id: String) -> String? {
        let texto = (mapa[id] ?? "").trimmingCharacters(in: .whitespaces)
        guard let valor = Double(texto), valor > 0 else { return nil }
        return texto
    }

    /// `enviarWhatsAppPersonalizado`.
    private func enviar(_ c: Cliente, plantilla: MensajePredeterminado?) {
        guard !c.tel.isEmpty else { return store.avisar("Sin teléfono", advertencia: true) }
        guard let plantilla, plantilla.tieneContenido else { return store.avisar("Configura primero la plantilla en Configuración", advertencia: true) }
        let tipo = cuerpoPara(c)
        var extras = ExtrasMensaje()
        switch tipo {
        case .linea:
            guard let linea = monto(lineas, c.id) ?? c["lineaCreditoGuardada"]?.text, (Double(linea) ?? 0) > 0 else {
                return store.avisar("Captura el monto de la línea de crédito", advertencia: true)
            }
            extras.lineaCredito = linea
        case .porfinalizar:
            guard let linea = monto(lineas, c.id) else { return store.avisar("Captura la línea de crédito", advertencia: true) }
            extras.lineaCredito = linea
        case .financing, .creditos:
            guard let linea = monto(lineas, c.id) else { return store.avisar("Captura la línea de crédito", advertencia: true) }
            extras.lineaCredito = linea
            if avanzadasPR(c, plantilla) {
                guard let enganche = monto(enganches, c.id) else { return store.avisar("Captura el enganche", advertencia: true) }
                extras.enganche = enganche
                extras.equipo = equipos[c.id] ?? ""
                extras.tipoProducto = tiposProducto[c.id] ?? ""
                extras.modelo = modelos[c.id] ?? ""
            }
        case .macropesos, .promociones:
            break
        }
        let mensaje = Mensajes.predeterminado(plantilla, cliente: c, cuerpo: tipo, extras: extras)
        if let url = WhatsApp.url(c.tel, mensaje: mensaje) { openURL(url) }
    }
}

private struct ArchivoCompartido: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct BuscadorOpcional: ViewModifier {
    let activo: Bool
    @Binding var texto: String

    func body(content: Content) -> some View {
        if activo {
            content.searchable(text: $texto, prompt: "Buscar nombre o teléfono")
        } else {
            content
        }
    }
}

/// Recently messaged contacts of a category; the administrator can release them early.
struct BloqueadosMensajeView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let categoria: CategoriaMensaje
    @State private var confirmacion: Confirmacion?

    var body: some View {
        let lista = Envios.bloqueados(categoria, en: store.clientes, dias: store.diasBloqueo)
        let dias = store.diasBloqueo.dias(categoria.claveBloqueo)
        NavigationStack {
            List {
                if lista.isEmpty {
                    Text("No hay contactos bloqueados en esta categoría").foregroundStyle(Tema.apagado).seccionTema()
                }
                Section {
                    ForEach(lista) { c in
                        let hace = Int((Envios.ahora() - Envios.ultimoMensaje(c)) / Envios.dia)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.nombre).font(.subheadline.weight(.medium))
                                Text(c.tel).font(Tipo.detalle.monospaced()).foregroundStyle(Tema.apagado)
                                Text("Enviado hace \(hace) día\(hace == 1 ? "" : "s") · faltan \(dias - hace) día\(dias - hace == 1 ? "" : "s")")
                                    .font(.caption2).foregroundStyle(Tema.advertencia)
                            }
                            Spacer()
                            if store.esAdmin {
                                Button {
                                    confirmacion = Confirmacion(titulo: "Desmarcar contacto", mensaje: "¿Desmarcar a \(c.nombre)? Volverá a aparecer en la lista de envío masivo.", boton: "Desmarcar") {
                                        if await store.desmarcarMensaje([c.id]) { store.avisar("✓ Contacto disponible de nuevo") }
                                    }
                                } label: {
                                    Image(systemName: "arrow.uturn.backward")
                                }
                                .buttonStyle(.pastilla(Tema.advertencia))
                            }
                        }
                    }
                } header: {
                    if !lista.isEmpty {
                        Text("Estos contactos recibieron un mensaje en los últimos \(dias) días. Puedes desmarcarlos para incluirlos de nuevo.").textCase(nil)
                    }
                }
                .seccionTema()
                if store.esAdmin, lista.count > 1 {
                    Button("↩ Desmarcar todos (\(lista.count))") {
                        confirmacion = Confirmacion(
                            titulo: "⚠️ Desmarcar todos",
                            mensaje: "¿Desmarcar los \(lista.count) contactos bloqueados de esta categoría? Todos volverán a aparecer en la lista de envío.",
                            boton: "Desmarcar \(lista.count)"
                        ) {
                            if await store.desmarcarMensaje(lista.map(\.id)) {
                                store.avisar("✓ \(lista.count) contactos disponibles de nuevo")
                            }
                        }
                    }
                    .foregroundStyle(Tema.advertencia)
                    .seccionTema()
                }
            }
            .fondoTema()
            .navigationTitle("Contactos bloqueados")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .confirmacion($confirmacion)
        }
        .capaDeEstado()
    }
}
