import Foundation
import SwiftUI
import AppKit
import Quartz

@MainActor
class DatasetViewModel: ObservableObject {
    @Published var pairs: [ImageCaptionPair] = []
    @Published var selectedID: UUID? = nil {
        didSet {
            // Persist selected image path when selection changes
            if let pair = selectedPair {
                UserDefaults.standard.set(pair.imageURL.path, forKey: "lastSelectedImagePath")
            }
            // Update Quick Look panel if visible
            updateQuickLookIfVisible()
        }
    }
    @Published var directoryURL: URL? = nil

    // Image cache and prefetch infrastructure
    let imageCache = ImageCacheActor()
    private(set) var prefetchTasks: [URL: Task<Void, Never>] = [:]

    // Folder tree - root of selected directory
    @Published var folderTree: [FileNode] = []

    // Expansion state for folder tree (using paths for persistence)
    @Published var expandedPaths: Set<String> = []

    // Incremented when a caption is reloaded from disk or saved, so
    // CaptionEditingContainer can re-sync its local text state.
    @Published var captionReloadToken: Int = 0

    // Live editing text — written directly by CaptionEditingContainer without
    // triggering objectWillChange. Read by saveSelected().
    var liveEditingText: String = ""

    // Dirty state managed with guarded transitions: objectWillChange only fires
    // when the dirty flag actually changes (false→true on first keystroke,
    // true→false on save/switch), NOT on every keystroke.
    private var _editingIsDirty: Bool = false
    var editingIsDirty: Bool { _editingIsDirty }

    func setEditingDirty(_ dirty: Bool) {
        guard _editingIsDirty != dirty else { return }
        _editingIsDirty = dirty
        objectWillChange.send()
    }

    // The root directory (stays fixed when navigating subdirs)
    private var rootDirectoryURL: URL? = nil

    // Track last selected image path for session restoration
    private var lastSelectedImagePath: String? = nil

    // URL resolvida com escopo de segurança (security-scoped)
    private var securedDirectoryURL: URL? = nil

    // Track if security-scoped access is active
    private var isAccessingSecurityScope = false

    // Key event monitor for Quick Look navigation
    private var qlKeyMonitor: Any? = nil

    let supportedImageExtensions = ["jpg", "jpeg", "png", "webp", "bmp", "tiff"]
    let supportedCaptionExtensions = ["txt", "caption"]

    var selectedPair: ImageCaptionPair? {
        guard let id = selectedID else { return nil }
        return pairs.first { $0.id == id }
    }

    var selectedIsDirty: Bool {
        _editingIsDirty || (selectedPair?.isDirty ?? false)
    }

    init() {
        // Restore expansion state from UserDefaults
        if let savedPaths = UserDefaults.standard.array(forKey: "expandedFolderPaths") as? [String] {
            expandedPaths = Set(savedPaths)
        }

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

            // Clear session state when choosing new root (fresh start)
            UserDefaults.standard.removeObject(forKey: "lastViewedFolderPath")
            UserDefaults.standard.removeObject(forKey: "lastSelectedImagePath")
            lastSelectedImagePath = nil

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

            // Cancel all in-flight prefetches and clear cache for new directory
            for (_, task) in prefetchTasks { task.cancel() }
            prefetchTasks.removeAll()
            print("[cache] cleared prefetch tasks for folder change")
            Task { await imageCache.clear() }
            print("[cache] cache cleared for folder change")

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
                securedDirectoryURL = resolved

                // Start and keep security-scoped access active
                startSecurityScopedAccess()

                // Build folder tree from root
                folderTree = buildFolderTree(from: resolved)

                // Load last selected image path before scanning
                lastSelectedImagePath = UserDefaults.standard.string(forKey: "lastSelectedImagePath")

                // Try to restore last viewed folder if available
                if let lastFolderPath = UserDefaults.standard.string(forKey: "lastViewedFolderPath"),
                   lastFolderPath.hasPrefix(resolved.path) {
                    // Security check: ensure last folder is within root
                    let lastFolderURL = URL(fileURLWithPath: lastFolderPath)
                    directoryURL = lastFolderURL
                } else {
                    directoryURL = resolved
                }

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
        // Cancel all in-flight prefetches
        for (_, task) in prefetchTasks { task.cancel() }
        prefetchTasks.removeAll()
        print("[cache] cleared prefetch tasks for folder change")

        // Clear cache (per user decision: clear entire cache on folder change)
        Task { await imageCache.clear() }
        print("[cache] cache cleared for folder change")

        directoryURL = url
        UserDefaults.standard.set(url.path, forKey: "lastViewedFolderPath")
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
                let pair = ImageCaptionPair(
                    imageURL: file,
                    captionURL: captionURL,
                    captionText: captionText,
                    savedCaptionText: captionText
                )
                newPairs.append(pair)
            }
        }

        newPairs.sort { $0.imageURL.lastPathComponent.localizedCaseInsensitiveCompare($1.imageURL.lastPathComponent) == .orderedAscending }
        pairs = newPairs

        // Try to restore last selected image if path matches
        if let restoredPath = lastSelectedImagePath,
           let matchingPair = pairs.first(where: { $0.imageURL.path == restoredPath }) {
            selectedID = matchingPair.id
            lastSelectedImagePath = nil // Clear after one-time restore
        } else {
            selectedID = pairs.first?.id
        }

        // Trigger initial prefetch around selected image (per user decision: prefetch on folder load)
        if let id = selectedID {
            triggerPrefetch(aroundID: id)
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

    func saveSelected() {
        guard let id = selectedID,
              let idx = pairs.firstIndex(where: { $0.id == id }) else { return }

        // Sync live editing text into pairs before saving
        if _editingIsDirty {
            pairs[idx].captionText = liveEditingText
        }

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
            // Update savedCaptionText after successful save
            pairs[idx].savedCaptionText = captionText
            _editingIsDirty = false
            // Signal CaptionEditingContainer to update its savedText
            captionReloadToken &+= 1
        } catch {
            print("[saveSelected] erro ao salvar caption:", error)
        }
    }

    func reloadCaptionForSelected() {
        guard let id = selectedID,
              let idx = pairs.firstIndex(where: { $0.id == id }) else { return }

        var pair = pairs[idx]
        if FileManager.default.fileExists(atPath: pair.captionURL.path) {
            let reloaded = (try? String(contentsOf: pair.captionURL, encoding: .utf8)) ?? ""
            pair.captionText = reloaded
            pair.savedCaptionText = reloaded
            pairs[idx] = pair
        }
        // Signal DetailView to re-sync its local caption text state
        captionReloadToken &+= 1
    }

    // MARK: - Context Menu Actions

    let qlPreviewHelper = QLPreviewHelper()

    func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openInFinder(url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openInTerminal(url: URL) {
        guard let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else { return }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: terminalURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error { print("[openInTerminal] error:", error) }
        }
    }

    func openWith(fileURL: URL, appURL: URL) {
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            if let error { print("[openWith] error:", error) }
        }
    }

    func quickLook(url: URL) {
        // Resign first responder to prevent NSTextView from hijacking QLPreviewPanel
        NSApp.keyWindow?.makeFirstResponder(nil)

        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            qlPreviewHelper.previewURL = url
            panel.dataSource = qlPreviewHelper
            panel.currentPreviewItemIndex = 0
            panel.reloadData()
            panel.orderFront(nil)
        }
    }

    func toggleQuickLook() {
        guard let pair = selectedPair else { return }

        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.orderOut(nil)
            removeQLKeyMonitor()
        } else {
            qlPreviewHelper.previewURL = pair.imageURL
            panel.dataSource = qlPreviewHelper
            panel.currentPreviewItemIndex = 0
            panel.reloadData()
            panel.orderFront(nil)
            installQLKeyMonitor()
        }
    }

    private func installQLKeyMonitor() {
        guard qlKeyMonitor == nil else { return }
        qlKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let panel = QLPreviewPanel.shared()!
            guard panel.isVisible else { return event }

            // Spacebar — toggle panel off
            if event.keyCode == 49 {
                panel.orderOut(nil)
                self.removeQLKeyMonitor()
                return nil // consume event
            }

            // Down arrow or Right arrow — next image
            if event.keyCode == 125 || event.keyCode == 124 {
                self.selectNextPair()
                return nil
            }

            // Up arrow or Left arrow — previous image
            if event.keyCode == 126 || event.keyCode == 123 {
                self.selectPreviousPair()
                return nil
            }

            return event
        }
    }

    private func removeQLKeyMonitor() {
        if let monitor = qlKeyMonitor {
            NSEvent.removeMonitor(monitor)
            qlKeyMonitor = nil
        }
    }

    func triggerPrefetch(aroundID id: UUID, displaySize: Int = 800) {
        guard let idx = pairs.firstIndex(where: { $0.id == id }) else { return }
        let lo = max(0, idx - 2)
        let hi = min(pairs.count - 1, idx + 2)
        let windowURLs = Set((lo...hi).map { pairs[$0].imageURL })

        // Cancel tasks outside the new window
        for (url, task) in prefetchTasks where !windowURLs.contains(url) {
            task.cancel()
            prefetchTasks.removeValue(forKey: url)
            print("[cache] cancelled prefetch for \(url.lastPathComponent)")
        }

        // Start tasks for window entries not yet cached or in-flight
        for i in lo...hi {
            let url = pairs[i].imageURL
            guard prefetchTasks[url] == nil else { continue }
            prefetchTasks[url] = Task.detached(priority: .utility) { [imageCache] in
                guard !Task.isCancelled else { return }
                // Check cache first (avoid redundant decode)
                if await imageCache.image(for: url) != nil { return }
                guard !Task.isCancelled else { return }
                if let img = loadImage(url: url, maxPixelSize: displaySize) {
                    let cost = img.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 }
                        ?? Int(img.size.width * 2 * img.size.height * 2 * 4)
                    await imageCache.insert(img, cost: cost, for: url)
                    print("[cache] prefetched \(url.lastPathComponent) (\(cost) bytes)")
                }
            }
        }
    }

    private func selectNextPair() {
        guard let id = selectedID,
              let idx = pairs.firstIndex(where: { $0.id == id }),
              idx + 1 < pairs.count else { return }
        selectedID = pairs[idx + 1].id
    }

    private func selectPreviousPair() {
        guard let id = selectedID,
              let idx = pairs.firstIndex(where: { $0.id == id }),
              idx > 0 else { return }
        selectedID = pairs[idx - 1].id
    }

    private func updateQuickLookIfVisible() {
        let panel = QLPreviewPanel.shared()!
        guard panel.isVisible, let pair = selectedPair else { return }
        qlPreviewHelper.previewURL = pair.imageURL
        panel.reloadData()
    }

    // MARK: - Folder Expansion State

    func toggleExpanded(path: String) {
        if expandedPaths.contains(path) {
            expandedPaths.remove(path)
        } else {
            expandedPaths.insert(path)
        }
        persistExpandedPaths()
    }

    func isExpanded(path: String) -> Bool {
        return expandedPaths.contains(path)
    }

    private func persistExpandedPaths() {
        let pathsArray = Array(expandedPaths)
        UserDefaults.standard.set(pathsArray, forKey: "expandedFolderPaths")
    }
}
