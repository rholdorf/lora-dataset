import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject var vm = DatasetViewModel()
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var loadedImage: NSImage? = nil

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
                                Text("sem caption")
                                    .italic()
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(pair.id)
                    }
                }
            }
            .frame(minWidth: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 12) {
                if let selectedID = vm.selectedID,
                   let idx = vm.pairs.firstIndex(where: { $0.id == selectedID }) {
                    let imageURL = vm.pairs[idx].imageURL
                    // Caption header
                    HStack {
                        Text(vm.pairs[idx].captionURL.lastPathComponent)
                            .font(.headline)
                        Spacer()
                        Button("Recarregar Caption") {
                            vm.reloadCaptionForSelected()
                        }
                    }
                    
                    // Image and caption editor
                    HSplitView {
                        Group {
                            if let nsImage = loadedImage {
                                ZoomablePannableImage(
                                    image: nsImage,
                                    scale: $imageScale,
                                    offset: $imageOffset
                                )
                                .frame(width: 400, height: 400)
                                .clipped()
                            } else {
                                Text("Não foi possível carregar a imagem.")
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(width: 400, height: 400)
                        .padding()
                        
                        VStack(alignment: .leading) {
                            Text("Caption / descrição:")
                                .font(.subheadline)
                            TextEditor(text: Binding(
                                get: { vm.pairs[idx].captionText },
                                set: { vm.pairs[idx].captionText = $0 }
                            ))
                            .font(.body)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.5))
                            )
                            .frame(minHeight: 200)

                            HStack {
                                Spacer()
                                Button("Salvar") {
                                    Task { vm.saveSelected() }
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    Text("Selecione uma imagem à esquerda.")
                        .foregroundColor(.secondary)
                        .italic()
                }
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 900, minHeight: 500)
        .onAppear {
            if let selectedID = vm.selectedID,
               let idx = vm.pairs.firstIndex(where: { $0.id == selectedID }) {
                loadedImage = NSImage(contentsOf: vm.pairs[idx].imageURL)
            }
        }
        .onChange(of: vm.selectedID) { newID in
            if let idx = vm.pairs.firstIndex(where: { $0.id == newID }) {
                loadedImage = NSImage(contentsOf: vm.pairs[idx].imageURL)
            } else {
                loadedImage = nil
            }
            imageScale = 1.0
            imageOffset = .zero
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
