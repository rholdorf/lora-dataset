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
                let imageURL = vm.pairs[idx].imageURL
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
                        if let nsImage = NSImage(contentsOf: imageURL) {
                            ZoomablePannableImage(
                                image: nsImage,
                                scale: $imageScale,
                                offset: $imageOffset
                            )
                            .id(selectedID)
                            // Fixed size to prevent resizing on zoom
                            .frame(width: 400, height: 400)
                            .padding()
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
                // Recreate detail on selection change to sync image and caption
                .id(selectedID)
                .onChange(of: selectedID) { _ in
                    imageScale = 1.0
                    imageOffset = .zero
                }
            } else {
                Text("Selecione uma imagem à esquerda.")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .frame(minWidth: 900, minHeight: 500)
    }
}
