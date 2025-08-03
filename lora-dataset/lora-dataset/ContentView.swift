import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject var vm = DatasetViewModel()
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    
    var body: some View {
        NavigationSplitView {
            VStack {
                HStack {
                    Button("Escolher Pasta") {
                        Task { await vm.chooseDirectory() }
                    }
                    if let dir = vm.directoryURL {
                        Text(dir.lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal)

                List(selection: $vm.selectedID) {
                    ForEach(vm.pairs) { pair in
                        HStack {
                            Text(pair.imageURL.lastPathComponent)
                            Spacer()
                            if pair.captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("sem caption").italic().foregroundColor(.secondary)
                            }
                        }
                        .tag(pair.id)
                    }
                }
            }
            .frame(minWidth: 250)

        } detail: {
            if let selectedID = vm.selectedID,
               let idx = vm.pairs.firstIndex(where: { $0.id == selectedID }) {
                let bindingCaption = Binding<String>(
                    get: { vm.pairs[idx].captionText },
                    set: { newText in
                        vm.pairs[idx].captionText = newText
                    }
                )

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(vm.pairs[idx].captionURL.lastPathComponent)
                            .font(.headline)
                        Spacer()
                        Button("Recarregar Caption") {
                            vm.reloadCaptionForSelected()
                        }
                    }

                    HSplitView {
                        if let nsImage = NSImage(contentsOf: vm.pairs[idx].imageURL) {
                            ZoomablePannableImage(
                                image: NSImage(contentsOf: vm.pairs[idx].imageURL),
                                scale: $imageScale,
                                offset: $imageOffset
                            )
                            .frame(maxWidth: 400, maxHeight: 400)
                            .padding()
                            .onChange(of: imageScale) { oldValue, _ in } // se quiser reagir
                            .onChange(of: vm.selectedID) { oldValue, _ in
                                // Reset do offset quando muda de imagem - o ZoomablePannableImage fará o fit automático
                                imageOffset = .zero
                            }
                        } else {
                            Text("Não foi possível carregar a imagem.")
                                .foregroundColor(.red)
                        }

                        VStack(alignment: .leading) {
                            Text("Caption / descrição:")
                                .font(.subheadline)
                            TextEditor(text: bindingCaption)
                                .font(.body)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.5)))
                                .frame(minHeight: 200)

                            HStack {
                                Spacer()
                                Button("Salvar") {
                                    Task {
                                        vm.saveSelected()
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    Spacer()
                }
                .padding()
            } else {
                Text("Selecione uma imagem à esquerda.")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }
}
