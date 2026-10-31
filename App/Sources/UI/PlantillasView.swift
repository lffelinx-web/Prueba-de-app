import SwiftUI

/// Each user's WhatsApp templates, as in the web app's configuration.
struct PlantillasView: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            Section("Recordatorios") {
                ForEach(TipoRecordatorio.allCases) { tipo in
                    NavigationLink {
                        EditorRecordatorioView(tipo: tipo)
                    } label: {
                        fila(tipo.titulo, tipo.descripcion, tipo.icono, configurada: store.plantillaRecordatorio(tipo) != nil)
                    }
                }
            }
            .seccionTema()
            Section("Mensajes predeterminados") {
                ForEach(CategoriaMensaje.conPlantilla) { categoria in
                    NavigationLink {
                        EditorMensajeView(categoria: categoria)
                    } label: {
                        fila(categoria.titulo, categoria.descripcion, categoria.icono, configurada: store.mensajePredeterminado(categoria)?.tieneContenido == true)
                    }
                }
            }
            .seccionTema()
        }
        .fondoTema()
        .navigationTitle("Plantillas")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fila(_ titulo: String, _ detalle: String, _ icono: String, configurada: Bool) -> some View {
        HStack(spacing: 12) {
            IconoCuadro(sistema: icono, color: Tema.acento)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo).font(.subheadline.weight(.semibold))
                Text(detalle).font(.caption).foregroundStyle(Tema.apagado)
            }
            Spacer()
            if !configurada { Etiqueta("Sin configurar", color: Tema.advertencia) }
        }
    }
}

/// Multi-line field with buttons that append placeholders like "[macropesos]".
struct CampoPlantilla: View {
    let titulo: String
    let ejemplo: String
    @Binding var texto: String
    var marcadores: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titulo).font(.caption.weight(.semibold)).foregroundStyle(Tema.apagado)
            TextField(ejemplo, text: $texto, axis: .vertical)
                .lineLimit(1...8)
                .campoTema()
            if !marcadores.isEmpty {
                HStack {
                    ForEach(marcadores, id: \.self) { marcador in
                        Button("+ \(marcador)") { texto += marcador }
                            .buttonStyle(.pastilla(Tema.acento))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// WhatsApp-style preview: `*texto*` shows in bold.
struct VistaPrevia: View {
    let mensaje: String

    var body: some View {
        let conNegritas = mensaje.replacingOccurrences(of: #"\*([^*\n]+)\*"#, with: "**$1**", options: .regularExpression)
        let texto = (try? AttributedString(markdown: conNegritas, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(mensaje)
        Text(texto)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Tema.whatsapp.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Tema.whatsapp.opacity(0.35), lineWidth: 1))
    }
}

private let clienteEjemplo = Cliente(raw: ["id": "ejemplo", "nombre": "Juan Pérez", "macropesos": 5000])

struct EditorRecordatorioView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let tipo: TipoRecordatorio
    @State private var plantilla = PlantillaRecordatorio()
    @State private var cargada = false
    @State private var error = ""

    var body: some View {
        Form {
            Section {
                CampoPlantilla(titulo: "1. Saludo inicial", ejemplo: "Ej. Hola, ", texto: $plantilla.saludo)
                CampoPlantilla(titulo: "2. Lugar", ejemplo: "Ej. te escribimos de Macropréstamos León.", texto: $plantilla.lugar)
                CampoPlantilla(titulo: "3. Cuerpo del mensaje", ejemplo: "Cuerpo del mensaje", texto: $plantilla.cuerpo, marcadores: tipo.marcadores)
            } footer: {
                Text("El nombre del cliente se agrega en negritas después del saludo.")
            }
            .seccionTema()
            if tipo == .macropesosDisponibles {
                Section {
                    Toggle("Opciones avanzadas (accesorio del catálogo)", isOn: $plantilla.avanzadasActivas)
                    if plantilla.avanzadasActivas {
                        CampoPlantilla(titulo: "Cuerpo con accesorio", ejemplo: "Ej. Con tus [macropesos] llévate [accesorio]", texto: $plantilla.cuerpoAvanzado,
                                       marcadores: ["[macropesos]", "[accesorio]", "[precio accesorio]", "[diferencia]"])
                    }
                }
                .seccionTema()
            }
            Section("Vista previa") {
                VistaPrevia(mensaje: Mensajes.recordatorio(plantilla, tipo: tipo, cliente: clienteEjemplo, extras: ExtrasMensaje(
                    numPago: "2°", lineaCredito: "10000",
                    accesorioNombre: plantilla.avanzadasActivas ? "Audífonos XYZ" : nil,
                    accesorioPrecio: plantilla.avanzadasActivas ? 1500 : nil)))
            }
            .listRowBackground(Color.clear)
            if !error.isEmpty {
                Text(error).foregroundStyle(Tema.peligro).seccionTema()
            }
        }
        .fondoTema()
        .navigationTitle(tipo.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    var limpia = plantilla
                    limpia.saludo = Texto.limpioConEspacios(limpia.saludo)
                    limpia.lugar = Texto.limpioConEspacios(limpia.lugar)
                    limpia.cuerpo = Texto.limpioConEspacios(limpia.cuerpo)
                    limpia.cuerpoAvanzado = Texto.limpioConEspacios(limpia.cuerpoAvanzado)
                    guard limpia.tieneContenido else {
                        error = "Completa al menos un campo."
                        return
                    }
                    Task { if await store.guardarPlantilla(limpia, tipo: tipo) { dismiss() } }
                }
                .bold()
            }
        }
        .onAppear {
            guard !cargada else { return }
            cargada = true
            plantilla = PlantillaRecordatorio(store.plantillasRecordatorio[tipo.rawValue])
        }
    }
}

struct EditorMensajeView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let categoria: CategoriaMensaje
    @State private var mensaje = MensajePredeterminado()
    @State private var cargado = false
    @State private var vista: CuerpoMensaje = .promociones
    @State private var error = ""

    private var opciones: [(CuerpoMensaje, String)] {
        switch categoria {
        case .sinrenovar: return [(.promociones, "Promociones"), (.macropesos, "Macropesos"), (.linea, "Línea")]
        case .porfinalizar: return [(.promociones, "Promociones"), (.porfinalizar, "Promociones extra")]
        case .prAprobadas: return [(.promociones, "Promociones"), (.financing, "Financing"), (.creditos, "Créditos")]
        default: return []
        }
    }

    var body: some View {
        Form {
            Section {
                CampoPlantilla(titulo: "1. Saludo inicial", ejemplo: "Ej. Hola, ", texto: $mensaje.saludo)
                CampoPlantilla(titulo: "2. Lugar", ejemplo: "Ej. te escribimos de Macropréstamos León.", texto: $mensaje.lugar)
                CampoPlantilla(titulo: "3. Cuerpo del mensaje (Promociones)", ejemplo: "Ej. Te recordamos que tienes una promoción especial", texto: $mensaje.cuerpo)
            }
            .seccionTema()

            switch categoria {
            case .sinrenovar:
                Section("Otras configuraciones") {
                    CampoPlantilla(titulo: "Cuerpo del mensaje (Macropesos)", ejemplo: "Ej. Tienes [macropesos] disponibles", texto: $mensaje.cuerpoMacro, marcadores: ["[macropesos]"])
                    CampoPlantilla(titulo: "Cuerpo del mensaje (Línea de crédito)", ejemplo: "Ej. Te ofrecemos una línea de crédito por [linea de crédito]", texto: $mensaje.cuerpoLinea, marcadores: ["[linea de crédito]"])
                }
                .seccionTema()
            case .porfinalizar:
                Section("Otras configuraciones") {
                    CampoPlantilla(titulo: "Cuerpo del mensaje (Promociones)", ejemplo: "Ej. Tienes [macropesos] disponibles y línea de [linea de crédito]", texto: $mensaje.cuerpoMacro,
                                   marcadores: ["[macropesos]", "[linea de crédito]"])
                }
                .seccionTema()
            case .prAprobadas:
                Section("Financing") {
                    CampoPlantilla(titulo: "Cuerpo del mensaje (Financing)", ejemplo: "Ej. Tu Financing por [linea de crédito]", texto: $mensaje.cuerpoFinancing, marcadores: ["[linea de crédito]"])
                    Toggle("Opciones avanzadas", isOn: $mensaje.advFinancing)
                    if mensaje.advFinancing {
                        CampoPlantilla(titulo: "Financing — avanzado", ejemplo: "Ej. Tu Financing por [linea de crédito] con enganche de [enganche] para tu [equipo]",
                                       texto: $mensaje.cuerpoFinancingAdv, marcadores: ["[linea de crédito]", "[enganche]", "[equipo]"])
                    }
                }
                .seccionTema()
                Section("Créditos") {
                    CampoPlantilla(titulo: "Cuerpo del mensaje (Créditos)", ejemplo: "Ej. Tu crédito por [linea de crédito]", texto: $mensaje.cuerpoCreditos, marcadores: ["[linea de crédito]"])
                    Toggle("Opciones avanzadas", isOn: $mensaje.advCreditos)
                    if mensaje.advCreditos {
                        CampoPlantilla(titulo: "Créditos — avanzado", ejemplo: "Ej. Tu crédito por [linea de crédito] con enganche de [enganche] para tu [tipo de producto] [modelo]",
                                       texto: $mensaje.cuerpoCreditosAdv, marcadores: ["[linea de crédito]", "[enganche]", "[tipo de producto]", "[modelo]"])
                    }
                }
                .seccionTema()
            default:
                EmptyView()
            }

            Section("Vista previa") {
                if !opciones.isEmpty {
                    Picker("Vista", selection: $vista) {
                        ForEach(opciones.indices, id: \.self) { i in Text(opciones[i].1).tag(opciones[i].0) }
                    }
                    .pickerStyle(.segmented)
                }
                VistaPrevia(mensaje: Mensajes.predeterminado(mensaje, cliente: clienteEjemplo, cuerpo: vista, extras: ExtrasMensaje(
                    lineaCredito: "10000", enganche: "2000", equipo: "Apple iPhone 15", tipoProducto: "iPhone", modelo: "iPhone 15 Pro")))
            }
            .listRowBackground(Color.clear)
            if !error.isEmpty {
                Text(error).foregroundStyle(Tema.peligro).seccionTema()
            }
        }
        .fondoTema()
        .navigationTitle(categoria.titulo)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") {
                    var limpio = mensaje
                    let rutas: [WritableKeyPath<MensajePredeterminado, String>] = [
                        \.saludo, \.lugar, \.cuerpo, \.cuerpoMacro, \.cuerpoLinea, \.cuerpoFinancing, \.cuerpoCreditos, \.cuerpoFinancingAdv, \.cuerpoCreditosAdv,
                    ]
                    for ruta in rutas {
                        limpio[keyPath: ruta] = Texto.limpioConEspacios(limpio[keyPath: ruta])
                    }
                    guard limpio.tieneContenido else {
                        error = "Completa al menos un campo."
                        return
                    }
                    Task { if await store.guardarMensaje(limpio, categoria: categoria) { dismiss() } }
                }
                .bold()
            }
        }
        .onAppear {
            guard !cargado else { return }
            cargado = true
            mensaje = MensajePredeterminado(store.mensajesPredeterminados[categoria.rawValue])
        }
    }
}
