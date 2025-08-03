//
//  ContentView.swift
//  lora-dataset
//
//  Created by Rui Holdorf on 03/08/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject var vm = DatasetViewModel()

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

                List(selection: $vm.selected) {
                    ForEach(vm.pairs) { pair in
                        HStack {
                            Text(pair.imageURL.lastPathComponent)
                            Spacer()
                            if pair.captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("sem caption").italic().foregroundColor(.secondary)
                            }
                        }
                        .tag(pair)
                    }
                }
            }
            .frame(minWidth: 250)

        } detail: {
            if let selected = vm.selected {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(selected.imageURL.lastPathComponent)
                            .font(.headline)
                        Spacer()
                        Button("Recarregar Caption") {
                            vm.reloadSelectedCaption()
                        }
                    }

                    HSplitView {
                        // Imagem
                        if let nsImage = NSImage(contentsOf: selected.imageURL) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 300, maxHeight: 300)
                                .border(.gray)
                                .padding()
                        } else {
                            Text("Não foi possível carregar a imagem.")
                                .foregroundColor(.red)
                        }

                        // Editor de caption
                        VStack(alignment: .leading) {
                            Text("Caption / descrição:")
                                .font(.subheadline)
                            TextEditor(text: binding(for: selected))
                                .font(.body)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.5)))
                                .frame(minHeight: 200)

                            HStack {
                                Spacer()
                                Button("Salvar") {
                                    vm.save(selected)
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

    // Helper para criar binding mutável do caption do par selecionado
    private func binding(for pair: ImageCaptionPair) -> Binding<String> {
        Binding(get: {
            vm.selected?.captionText ?? ""
        }, set: { newVal in
            if var sel = vm.selected, sel.id == pair.id {
                sel.captionText = newVal
                vm.selected = sel
                // Also update in array for live sync
                if let idx = vm.pairs.firstIndex(of: sel) {
                    vm.pairs[idx] = sel
                }
            }
        })
    }
}
