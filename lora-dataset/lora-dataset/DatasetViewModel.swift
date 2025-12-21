import Foundation
import SwiftUI
import AppKit

@MainActor
class DatasetViewModel: ObservableObject {
    @Published var pairs: [ImageCaptionPair] = []
    @Published var selectedID: UUID? = nil
    @Published var directoryURL: URL? = nil

    // Folder tree - root of selected directory
    @Published var folderTree: [FileNode] = []

    // The root directory (stays fixed when navigating subdirs)
    private var rootDirectoryURL: URL? = nil

    // URL resolvida com escopo de segurança (security-scoped)
    private var securedDirectoryURL: URL? = nil

    // Track if security-scoped access is active
    private var isAccessingSecurityScope = false

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

    // Start security-scoped access and keep it active
    private func startSecurityScopedAccess() {
        // Stop any previous access first
        if isAccessingSecurityScope {
            securedDirectoryURL?.stopAccessingSecurityScopedResource()
            isAccessingSecurityScope = false
        }
        // Start new access
        if let secured = securedDirectoryURL {
            isAccessingSecurityScope = secured.startAccessingSecurityScopedResource()
        }
    }

    func chooseDirectory() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Selecione o diretório do dataset"
        if panel.runModal() == .OK, let url = panel.url {
            // Save as both root and current directory
            rootDirectoryURL = url
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
                    print("Bookmark estava stale; considerar recriar.")
                }
            } catch {
                print("Erro resolvendo bookmark para uso imediato:", error)
                securedDirectoryURL = url
            }

            // Start and keep security-scoped access active
            startSecurityScopedAccess()

            // Build folder tree from root
            folderTree = buildFolderTree(from: url)

            // Scan files in current directory
            scanCurrentDirectory()
        }
    }

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
                rootDirectoryURL = resolved
                directoryURL = resolved
                securedDirectoryURL = resolved

                // Start and keep security-scoped access active
                startSecurityScopedAccess()

                // Build folder tree from root
                folderTree = buildFolderTree(from: resolved)

                // Scan files
                scanCurrentDirectory()
            } catch {
                print("Erro resolvendo bookmark salvo:", error)
            }
        }
    }

    // Build complete folder tree (no lazy loading)
    // Note: Security-scoped access must be active before calling this
    private func buildFolderTree(from url: URL) -> [FileNode] {
        return buildFolderTreeRecursive(from: url, maxDepth: 10)
    }

    private func buildFolderTreeRecursive(from url: URL, maxDepth: Int) -> [FileNode] {
        guard maxDepth > 0 else { return [] }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { itemURL in
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let children = buildFolderTreeRecursive(from: itemURL, maxDepth: maxDepth - 1)
                return FileNode(url: itemURL, children: children)
            }
            return nil
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Navigate to a folder (called when user clicks folder in tree)
    func navigateToFolder(_ url: URL) {
        directoryURL = url
        scanCurrentDirectory()
    }

    // Scan current directory for image/caption pairs
    // Note: Security-scoped access must be active before calling this
    private func scanCurrentDirectory() {
        guard let folder = directoryURL else { return }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            pairs = []
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
                if fm.fileExists(atPath: captionURL.path) {
                    captionText = (try? String(contentsOf: captionURL, encoding: .utf8)) ?? ""
                }
                let pair = ImageCaptionPair(imageURL: file, captionURL: captionURL, captionText: captionText)
                newPairs.append(pair)
            }
        }

        newPairs.sort { $0.imageURL.lastPathComponent.localizedCaseInsensitiveCompare($1.imageURL.lastPathComponent) == .orderedAscending }
        pairs = newPairs
        selectedID = pairs.first?.id
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

    func saveSelected() {
        guard let id = selectedID,
              let idx = pairs.firstIndex(where: { $0.id == id }) else { return }

        let pair = pairs[idx]
        let captionText = pair.captionText
        let captionURL = pair.captionURL

        do {
            try withScopedDirectoryAccess {
                let folder = captionURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try captionText.write(to: captionURL, atomically: true, encoding: .utf8)

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

        var pair = pairs[idx]
        if FileManager.default.fileExists(atPath: pair.captionURL.path) {
            pair.captionText = (try? String(contentsOf: pair.captionURL, encoding: .utf8)) ?? ""
            pairs[idx] = pair
        }
    }
}
