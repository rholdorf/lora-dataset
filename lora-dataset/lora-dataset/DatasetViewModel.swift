import Foundation
import SwiftUI
import AppKit

@MainActor
class DatasetViewModel: ObservableObject {
    @Published var pairs: [ImageCaptionPair] = []
    @Published var selectedID: UUID? = nil
    @Published var directoryURL: URL? = nil

    // Folder tree navigation
    @Published var folderTree: [FileNode] = []
    @Published var selectedFolderID: UUID? = nil

    // URL resolvida com escopo de segurança (security-scoped)
    private var securedDirectoryURL: URL? = nil

    let supportedImageExtensions = ["jpg", "jpeg", "png", "webp", "bmp", "tiff"]
    let supportedCaptionExtensions = ["txt", "caption"]

    var selectedPair: ImageCaptionPair? {
        guard let id = selectedID else { return nil }
        return pairs.first { $0.id == id }
    }

    var selectedFolderURL: URL? {
        guard let id = selectedFolderID else { return nil }
        return findNodeByID(id, in: folderTree)?.url
    }

    // Helper to find a node by ID in the tree
    private func findNodeByID(_ id: UUID, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.id == id {
                return node
            }
            if let children = node.children {
                if let found = findNodeByID(id, in: children) {
                    return found
                }
            }
        }
        return nil
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

        // Build folder tree for navigation
        folderTree = buildFolderTree(from: folder, depth: 1)
    }

    // Build folder tree structure recursively
    func buildFolderTree(from url: URL, depth: Int = 1) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return contents.compactMap { itemURL in
            let isDir = (try? itemURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                // Only load children if depth allows (lazy loading)
                let children: [FileNode]? = depth > 0
                    ? buildFolderTree(from: itemURL, depth: depth - 1)
                    : []  // Empty array = folder, will load on expand
                return FileNode(url: itemURL, children: children)
            }
            return nil  // Skip files - they go in detail view
        }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // Load children for a node (lazy loading on expand)
    func loadChildrenForNode(nodeID: UUID) {
        guard let node = findNodeByID(nodeID, in: folderTree) else { return }

        // Load children with depth 1
        let children = buildFolderTree(from: node.url, depth: 1)

        // Update the node in the tree
        updateNodeChildren(nodeID: nodeID, children: children, in: &folderTree)
    }

    // Helper to update a node's children in the tree
    private func updateNodeChildren(nodeID: UUID, children: [FileNode], in nodes: inout [FileNode]) {
        for i in 0..<nodes.count {
            if nodes[i].id == nodeID {
                nodes[i].children = children
                return
            }
            if var nodeChildren = nodes[i].children {
                updateNodeChildren(nodeID: nodeID, children: children, in: &nodeChildren)
                nodes[i].children = nodeChildren
            }
        }
    }

    // Select a folder and load its pairs
    func selectFolder(_ url: URL) async {
        directoryURL = url
        await scanDirectory(url)
        // Note: We keep the same securedDirectoryURL since the parent bookmark covers subdirectories
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
