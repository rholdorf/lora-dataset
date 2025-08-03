import Foundation
import SwiftUI
import AppKit

@MainActor
class DatasetViewModel: ObservableObject {
    @Published var pairs: [ImageCaptionPair] = []
    @Published var selectedID: UUID? = nil
    @Published var directoryURL: URL? = nil

    // URL resolvida com escopo de segurança (security-scoped)
    private var securedDirectoryURL: URL? = nil

    let supportedImageExtensions = ["jpg", "jpeg", "png", "webp", "bmp", "tiff"]
    let supportedCaptionExtensions = ["txt", "caption"]

    var selectedPair: ImageCaptionPair? {
        guard let id = selectedID else { return nil }
        return pairs.first { $0.id == id }
    }

    init() {
        Task {
            await restorePreviousDirectoryIfAvailable()
        }
    }

    func chooseDirectory() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Selecione o diretório do dataset"
        if panel.runModal() == .OK, let url = panel.url {
            directoryURL = url

            // Criar bookmark com escopo e persistir
            do {
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                UserDefaults.standard.set(bookmarkData, forKey: "lastDatasetFolderBookmark")
            } catch {
                print("Erro criando bookmark:", error)
            }

            // Resolver o bookmark imediatamente para obter a URL com escopo válida
            do {
                var isStale = false
                let bookmarkData = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                let resolved = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                securedDirectoryURL = resolved
                if isStale {
                    // Se estiver stale, poderia recriar o bookmark mais adiante
                    print("Bookmark estava stale; considerar recriar.")
                }
            } catch {
                print("Erro resolvendo bookmark para uso imediato:", error)
                // fallback simples
                securedDirectoryURL = url
            }

            await scanDirectory(url)
        }
    }

    // Restaura pasta anterior se houver bookmark salvo
    func restorePreviousDirectoryIfAvailable() async {
        if let bookmarkData = UserDefaults.standard.data(forKey: "lastDatasetFolderBookmark") {
            var isStale = false
            do {
                let resolved = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    print("Bookmark restaurado está stale.")
                }
                directoryURL = resolved
                securedDirectoryURL = resolved
                await scanDirectory(resolved)
            } catch {
                print("Erro resolvendo bookmark salvo:", error)
            }
        }
    }

    // Helper que ativa o escopo antes de executar e desativa depois
    private func withScopedDirectoryAccess<T>(_ work: () throws -> T) rethrows -> T {
        var didStart = false
        if let secured = securedDirectoryURL, secured.startAccessingSecurityScopedResource() {
            didStart = true
        }
        defer {
            if didStart {
                securedDirectoryURL?.stopAccessingSecurityScopedResource()
            }
        }
        return try work()
    }

    func scanDirectory(_ folder: URL) async {
        pairs = []
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return
        }

        var captionMap: [String: URL] = [:]
        for file in contents {
            let ext = file.pathExtension.lowercased()
            if supportedCaptionExtensions.contains(ext) {
                let base = file.deletingPathExtension().lastPathComponent
                captionMap[base] = file
            }
        }

        var newPairs: [ImageCaptionPair] = []
        for file in contents {
            let ext = file.pathExtension.lowercased()
            if supportedImageExtensions.contains(ext) {
                let base = file.deletingPathExtension().lastPathComponent
                let captionURL: URL
                if let existing = captionMap[base] {
                    captionURL = existing
                } else {
                    captionURL = folder.appendingPathComponent("\(base).txt")
                }

                var captionText = ""
                if FileManager.default.fileExists(atPath: captionURL.path) {
                    captionText = (try? String(contentsOf: captionURL, encoding: .utf8)) ?? ""
                }
                let pair = ImageCaptionPair(imageURL: file, captionURL: captionURL, captionText: captionText)
                newPairs.append(pair)
            }
        }

        newPairs.sort { $0.imageURL.lastPathComponent < $1.imageURL.lastPathComponent }
        pairs = newPairs
        selectedID = pairs.first?.id
    }

    func saveSelected() {
        guard let id = selectedID,
              let idx = pairs.firstIndex(where: { $0.id == id }) else { return }

        let pair = pairs[idx]
        let captionText = pair.captionText
        let captionURL = pair.captionURL

        do {
            try withScopedDirectoryAccess {
                // Garante diretório
                let folder = captionURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try captionText.write(to: captionURL, atomically: true, encoding: .utf8)

                // Verificação
                let reloaded = try String(contentsOf: captionURL, encoding: .utf8)
                if reloaded != captionText {
                    print("[saveSelected] aviso: conteúdo lido de volta difere do escrito.")
                } else {
                    print("[saveSelected] salvo com sucesso em \(captionURL.path)")
                }
            }
        } catch {
            print("[saveSelected] erro ao salvar caption:", error)
        }
    }

    func reloadCaptionForSelected() {
        guard let id = selectedID,
              let idx = pairs.firstIndex(where: { $0.id == id }) else { return }

        do {
            var pair = pairs[idx]
            if FileManager.default.fileExists(atPath: pair.captionURL.path) {
                pair.captionText = (try? String(contentsOf: pair.captionURL, encoding: .utf8)) ?? ""
                pairs[idx] = pair
            }
        }
    }
}
