import PhotosUI
import SwiftUI

/// Herramientas → Fotos a PDF: pick photos, order them, share one light PDF.
struct FotosPDFView: View {
    @EnvironmentObject private var store: Store
    @State private var seleccion: [PhotosPickerItem] = []
    @State private var paginas: [Pagina] = []
    @State private var nombre = ""
    @State private var cargando = false
    @State private var archivo: URL?

    struct Pagina: Identifiable {
        let id = UUID()
        let datos: Data
        let miniatura: UIImage
    }

    private struct ArchivoPDF: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    private static let fecha: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "dd-MM-yyyy"
        return f
    }()

    var body: some View {
        List {
            Section {
                PhotosPicker(selection: $seleccion, maxSelectionCount: 50, selectionBehavior: .ordered, matching: .images) {
                    HStack(spacing: 12) {
                        IconoCuadro(sistema: "photo.on.rectangle.angled", color: Tema.Seccion.azul, lado: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(paginas.isEmpty ? "Elegir fotos" : "Agregar más fotos")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.texto)
                            Text("Se agregan en el orden en que las tocas").font(Tipo.detalle).foregroundStyle(Tema.apagado)
                        }
                        Spacer()
                        if cargando { ProgressView() }
                    }
                }
                .disabled(cargando)
            }
            .seccionTema()

            if !paginas.isEmpty {
                Section {
                    ForEach(Array(paginas.enumerated()), id: \.element.id) { i, pagina in
                        HStack(spacing: 12) {
                            Image(uiImage: pagina.miniatura)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Tema.borde, lineWidth: 1))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Página \(i + 1)").font(.system(size: 15, weight: .semibold)).foregroundStyle(Tema.texto)
                                Text(peso(pagina.datos.count)).font(Tipo.detalle).foregroundStyle(Tema.apagado)
                            }
                        }
                    }
                    .onMove { paginas.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { paginas.remove(atOffsets: $0) }
                } header: {
                    Text("\(paginas.count) página\(paginas.count == 1 ? "" : "s")")
                } footer: {
                    Text("Arrastra ☰ para cambiar el orden. Cada página toma el tamaño de su foto.")
                }
                .seccionTema()

                Section("Nombre del archivo") {
                    TextField("Fotos \(FotosPDFView.fecha.string(from: Date()))", text: $nombre)
                        .textInputAutocapitalization(.words)
                }
                .seccionTema()

                Section {
                    Button(action: crear) {
                        Label("Crear PDF y compartir", systemImage: "doc.richtext")
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.pastilla(Tema.acento, relleno: true))
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    Button("Empezar de nuevo", role: .destructive) {
                        paginas = []
                        nombre = ""
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .environment(\.editMode, .constant(paginas.isEmpty ? .inactive : .active))
        .fondoTema()
        .navigationTitle("Fotos a PDF")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: seleccion) { _, nuevos in
            guard !nuevos.isEmpty else { return }
            Task { await cargar(nuevos) }
        }
        .sheet(item: Binding(get: { archivo.map(ArchivoPDF.init) }, set: { archivo = $0?.url })) { item in
            HojaCompartir(elementos: [item.url])
        }
    }

    private func peso(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func cargar(_ elementos: [PhotosPickerItem]) async {
        cargando = true
        defer { cargando = false; seleccion = [] }
        var nuevas: [Pagina] = []
        for elemento in elementos {
            guard let datos = try? await elemento.loadTransferable(type: Data.self),
                  let imagen = UIImage(data: datos) else { continue }
            let pagina: Pagina? = await Task.detached(priority: .userInitiated) {
                guard let jpeg = PDF.preparar(imagen) else { return nil }
                let miniatura = imagen.preparingThumbnail(of: CGSize(width: 160, height: 160)) ?? imagen
                return Pagina(datos: jpeg, miniatura: miniatura)
            }.value
            if let pagina { nuevas.append(pagina) }
        }
        if nuevas.count < elementos.count {
            store.avisar("No se pudieron leer \(elementos.count - nuevas.count) foto(s)", advertencia: true)
        }
        paginas.append(contentsOf: nuevas)
    }

    private func crear() {
        let titulo = nombre.isEmpty ? "Fotos \(FotosPDFView.fecha.string(from: Date()))" : nombre
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(PDF.nombreArchivo(titulo))
        let datos = PDF.crear(paginas.map(\.datos))
        do {
            try datos.write(to: url, options: .atomic)
            store.avisar("✓ PDF listo · \(paginas.count) página\(paginas.count == 1 ? "" : "s") · \(peso(datos.count))")
            archivo = url
        } catch {
            store.avisar("No se pudo crear el PDF: \(error.localizedDescription)", advertencia: true)
        }
    }
}
