import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var vm = DatasetViewModel()
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var loadedImage: NSImage? = nil
    /// File modification date of `loadedImage`, captured at decode time.
    /// Used by the scroll-zoom freshness check as the baseline — independent
    /// of the cache, since the cache may have been evicted (watchdog,
    /// memory pressure) while `loadedImage` is still on screen.
    @State private var loadedImageMtime: Date? = nil
    @State private var showSpinner: Bool = false
    @State private var loadError: Bool = false
    @State private var loadErrorFilename: String = ""

    // In-flight image load task — cancelled on each new selection (LIFO behaviour).
    @State private var currentLoadTask: Task<Void, Never>? = nil
    // Debounced prefetch task — only fires after user pauses navigation.
    @State private var prefetchDebounceTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationSplitView {
            SidebarView(vm: vm)
        } detail: {
            DetailView(
                vm: vm,
                loadedImage: $loadedImage,
                loadedImageMtime: $loadedImageMtime,
                imageScale: $imageScale,
                imageOffset: $imageOffset,
                showSpinner: $showSpinner,
                loadError: $loadError,
                loadErrorFilename: $loadErrorFilename
            )
        }
        .frame(minWidth: 900, minHeight: 500)
        .navigationTitle("")
        .toolbar {
            // Leading: Folder navigation
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task { await vm.chooseDirectory() }
                } label: {
                    Label("Escolher Pasta", systemImage: "folder.badge.plus")
                }
                .help("Escolher pasta de dataset")

                if let dir = vm.directoryURL {
                    Text(dir.path)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(dir.path)
                }
            }

            // Trailing: Caption actions
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    vm.reloadCaptionForSelected()
                } label: {
                    Label("Recarregar", systemImage: "arrow.clockwise")
                }
                .help("Recarregar caption do disco")
                .disabled(vm.detailID == nil)

                Button {
                    vm.saveSelected()
                } label: {
                    Label("Salvar", systemImage: "square.and.arrow.down")
                }
                .help("Salvar caption (Cmd+S)")
                .disabled(!vm.selectedIsDirty)
            }
        }
        .focusedValue(\.datasetViewModel, vm)
        // When the debounced detailID actually changes, load the image.
        .onChange(of: vm.detailID) {
            loadImageForSelection()
        }
        // When the watchdog or activation observer refreshes the cache for
        // the displayed image, reload from cache (fast path will hit the
        // freshly-decoded entry).
        .onChange(of: vm.imageRefreshToken) {
            loadImageForSelection()
        }
    }

    private func loadImageForSelection() {
        currentLoadTask?.cancel()
        prefetchDebounceTask?.cancel()

        guard let id = vm.detailID,
              let pair = vm.pairs.first(where: { $0.id == id }) else {
            loadedImage = nil
            loadedImageMtime = nil
            if showSpinner    { showSpinner    = false }
            if loadError      { loadError      = false }
            if imageScale != 1.0 { imageScale  = 1.0  }
            if imageOffset != .zero { imageOffset = .zero }
            currentLoadTask = nil
            prefetchDebounceTask = nil
            return
        }

        let url = pair.imageURL
        let capturedID = id

        currentLoadTask = Task { @MainActor in
            // Fast path: cache hit
            if let cached = await vm.imageCache.image(for: url) {
                let cachedMtime = await vm.imageCache.cachedMtime(for: url)
                guard !Task.isCancelled, self.vm.detailID == capturedID else { return }
                if self.imageScale  != 1.0   { self.imageScale  = 1.0   }
                if self.imageOffset != .zero  { self.imageOffset = .zero }
                if self.showSpinner           { self.showSpinner = false }
                if self.loadError             { self.loadError   = false }
                self.loadedImage = cached
                self.loadedImageMtime = cachedMtime
                print("[cache] hit for \(url.lastPathComponent)")
                scheduleDebouncedPrefetch(aroundID: capturedID)
                return
            }

            print("[cache] miss for \(url.lastPathComponent)")

            // Slow path: cache miss — start 150ms delayed spinner.
            let spinnerTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard !Task.isCancelled,
                      self.vm.detailID == capturedID else { return }
                self.showSpinner = true
            }

            let result = await Task.detached(priority: .userInitiated) { () -> (NSImage?, Date?) in
                // Capture mtime BEFORE decode so a later file write is detected
                // on the next freshness check rather than being silently absorbed.
                let mtime = fileModificationDate(url)
                let img = loadImage(url: url, maxPixelSize: 800)
                return (img, mtime)
            }.value

            spinnerTask.cancel()
            guard !Task.isCancelled, self.vm.detailID == capturedID else { return }
            if self.showSpinner { self.showSpinner = false }

            if let img = result.0 {
                if self.imageScale  != 1.0   { self.imageScale  = 1.0   }
                if self.imageOffset != .zero  { self.imageOffset = .zero }
                if self.loadError             { self.loadError   = false }
                self.loadedImage = img
                self.loadedImageMtime = result.1
                let cost = img.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 }
                    ?? Int(img.size.width * img.size.height * 4)
                await vm.imageCache.insert(img, cost: cost, mtime: result.1, for: url)
                scheduleDebouncedPrefetch(aroundID: capturedID)
            } else {
                self.loadedImage = nil
                self.loadedImageMtime = nil
                if self.imageScale  != 1.0   { self.imageScale  = 1.0   }
                if self.imageOffset != .zero  { self.imageOffset = .zero }
                if !self.loadError            { self.loadError   = true  }
                self.loadErrorFilename = url.lastPathComponent
            }
        }
    }

    private func scheduleDebouncedPrefetch(aroundID id: UUID) {
        prefetchDebounceTask?.cancel()
        prefetchDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            vm.triggerPrefetch(aroundID: id)
        }
    }
}

// MARK: - Sidebar (owns selectedFileID — isolates per-keypress re-renders)

/// Extracted into its own View so that arrow-key selection changes only
/// re-evaluate this small view tree, NOT the entire ContentView (which
/// includes the detail pane, toolbar, NavigationSplitView scaffolding).
struct SidebarView: View {
    @ObservedObject var vm: DatasetViewModel
    @State private var selectedFileID: UUID? = nil
    @State private var detailDebounceTask: Task<Void, Never>? = nil
    @State private var isSyncingSelection: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            ScrollViewReader { proxy in
                List(selection: $selectedFileID) {
                    if !vm.folderTree.isEmpty {
                        Section("Pastas") {
                            FolderTreeView(nodes: vm.folderTree, vm: vm)
                        }
                    }

                    Section("Arquivos (\(vm.pairs.count))") {
                        ForEach(vm.pairs) { pair in
                            FileRowView(pair: pair, isDetailSelected: pair.id == vm.detailID && vm.editingIsDirty)
                                .tag(pair.id)
                                .id(pair.id)
                                .contextMenu {
                                    Button {
                                        vm.revealInFinder(url: pair.imageURL)
                                    } label: {
                                        Label("Reveal in Finder", systemImage: "folder.badge.magnifyingglass")
                                    }

                                    OpenWithMenu(fileURL: pair.imageURL, vm: vm)

                                    Divider()

                                    Button {
                                        vm.quickLook(url: pair.imageURL)
                                    } label: {
                                        Label("Quick Look", systemImage: "eye")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.sidebar)
                .onKeyPress(.space) {
                    vm.toggleQuickLook()
                    return .handled
                }
                .onChange(of: vm.pairs) {
                    if let id = vm.selectedID {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 280)
        .onAppear {
            selectedFileID = vm.selectedID
            commitDetailID()
        }
        .onChange(of: selectedFileID) {
            guard !isSyncingSelection else { return }
            scheduleDetailDebounce()
        }
        .onChange(of: vm.selectedID) {
            guard !isSyncingSelection else { return }
            isSyncingSelection = true
            if selectedFileID != vm.selectedID {
                selectedFileID = vm.selectedID
            }
            isSyncingSelection = false
            commitDetailID()
        }
        .onChange(of: vm.pairs) {
            isSyncingSelection = true
            selectedFileID = vm.selectedID
            isSyncingSelection = false
            commitDetailID()
        }
    }

    private func scheduleDetailDebounce() {
        detailDebounceTask?.cancel()
        detailDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            isSyncingSelection = true
            vm.selectedID = self.selectedFileID
            vm.detailID = self.selectedFileID
            isSyncingSelection = false
        }
    }

    private func commitDetailID() {
        detailDebounceTask?.cancel()
        detailDebounceTask = nil
        isSyncingSelection = true
        vm.selectedID = selectedFileID
        vm.detailID = selectedFileID
        isSyncingSelection = false
    }
}

// MARK: - File Row (minimal, no vm dependency for fast diffing)

/// Each row is its own View struct so SwiftUI can skip re-evaluation
/// when the row's inputs haven't changed (Equatable diffing).
struct FileRowView: View {
    let pair: ImageCaptionPair
    let isDetailSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(pair.imageURL.lastPathComponent)
            if pair.isDirty || isDetailSelected {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundColor(.orange)
            }
            Spacer()
            if pair.hasEmptyCaption {
                Text("sem caption")
                    .font(.caption)
                    .italic()
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Open With Menu (lazy — only evaluated when menu is shown)

struct OpenWithMenu: View {
    let fileURL: URL
    @ObservedObject var vm: DatasetViewModel

    var body: some View {
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: fileURL)
        let otherApps = apps
            .filter { $0 != defaultApp }
            .sorted { $0.deletingPathExtension().lastPathComponent.localizedCaseInsensitiveCompare(
                $1.deletingPathExtension().lastPathComponent) == .orderedAscending }

        Menu("Open With") {
            if let defaultAppURL = defaultApp {
                Button {
                    vm.openWith(fileURL: fileURL, appURL: defaultAppURL)
                } label: {
                    Label {
                        Text(appName(from: defaultAppURL))
                            .bold()
                    } icon: {
                        Image(nsImage: appIcon(for: defaultAppURL))
                    }
                }
                Divider()
            }

            ForEach(otherApps, id: \.self) { appURL in
                Button {
                    vm.openWith(fileURL: fileURL, appURL: appURL)
                } label: {
                    Label {
                        Text(appName(from: appURL))
                    } icon: {
                        Image(nsImage: appIcon(for: appURL))
                    }
                }
            }

            Divider()

            Button("Other...") {
                chooseApp(for: fileURL)
            }
        }
    }

    private func appName(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    private func appIcon(for appURL: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }

    private func chooseApp(for fileURL: URL) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let appURL = panel.url {
            vm.openWith(fileURL: fileURL, appURL: appURL)
        }
    }
}

// MARK: - Folder Tree

struct FolderTreeView: View {
    let nodes: [FileNode]
    @ObservedObject var vm: DatasetViewModel

    var body: some View {
        ForEach(nodes) { node in
            FolderNodeView(node: node, vm: vm)

            if let children = node.children, !children.isEmpty, vm.isExpanded(path: node.url.path) {
                FolderTreeView(nodes: children, vm: vm)
                    .padding(.leading, 16)
            }
        }
    }
}

struct FolderNodeView: View {
    let node: FileNode
    @ObservedObject var vm: DatasetViewModel

    private var hasChildren: Bool {
        node.children?.isEmpty == false
    }

    private var isExpanded: Bool {
        vm.isExpanded(path: node.url.path)
    }

    var body: some View {
        HStack(spacing: 4) {
            if hasChildren {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.toggleExpanded(path: node.url.path)
                    }
            } else {
                Color.clear.frame(width: 12)
            }

            Label(node.name, systemImage: "folder")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    vm.navigateToFolder(node.url)
                }
        }
        .contextMenu {
            Button {
                vm.openInFinder(url: node.url)
            } label: {
                Label("Open in Finder", systemImage: "folder")
            }

            Button {
                vm.openInTerminal(url: node.url)
            } label: {
                Label("Open in Terminal", systemImage: "terminal")
            }
        }
    }
}

// MARK: - Detail View

struct DetailView: View {
    @ObservedObject var vm: DatasetViewModel
    @Binding var loadedImage: NSImage?
    @Binding var loadedImageMtime: Date?
    @Binding var imageScale: CGFloat
    @Binding var imageOffset: CGSize
    @Binding var showSpinner: Bool
    @Binding var loadError: Bool
    @Binding var loadErrorFilename: String

    @State private var captionFilename: String = ""
    @State private var staleCheckTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.detailID != nil {
                Text(captionFilename)
                    .font(.headline)

                HSplitView {
                    Group {
                        if loadError {
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(.secondary)
                                Text(loadErrorFilename)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 400, height: 400)
                        } else if let nsImage = loadedImage {
                            ZoomablePannableImage(
                                image: nsImage,
                                scale: $imageScale,
                                offset: $imageOffset,
                                onScrollZoom: scheduleStaleCheck
                            )
                            .frame(width: 400, height: 400)
                            .clipped()
                            .overlay {
                                if showSpinner {
                                    ZStack {
                                        Color.black.opacity(0.3)
                                        ProgressView()
                                            .controlSize(.large)
                                    }
                                }
                            }
                        } else if showSpinner {
                            ZStack {
                                Color.black.opacity(0.3)
                                    .frame(width: 400, height: 400)
                                ProgressView()
                                    .controlSize(.large)
                            }
                        } else {
                            Text("Nao foi possivel carregar a imagem.")
                                .foregroundColor(.red)
                        }
                    }
                    .frame(width: 400, height: 400)
                    .padding()

                    CaptionEditingContainer(vm: vm)
                }
            } else {
                Text("Selecione uma imagem à esquerda.")
                    .foregroundColor(.secondary)
                    .italic()
            }
            Spacer()
        }
        .padding()
        .onChange(of: vm.detailID) {
            syncCaptionFilename()
        }
        .onAppear {
            syncCaptionFilename()
        }
    }

    private func syncCaptionFilename() {
        guard let id = vm.detailID,
              let pair = vm.pairs.first(where: { $0.id == id }) else {
            captionFilename = ""
            return
        }
        captionFilename = pair.captionURL.lastPathComponent
    }

    /// Called from `ZoomablePannableImage` after each scroll-wheel zoom step.
    /// Detection of new file versions is owned by the watchdog / activation
    /// observer in DatasetViewModel — this hook just makes sure the view is
    /// showing whatever the cache currently holds. Cache-only, no disk I/O.
    ///
    /// In practice the watchdog already triggers an explicit reload via
    /// `imageRefreshToken`, so this is a belt-and-braces sync for the rare
    /// case where the cache was refreshed but the view's `loadedImage` is
    /// still pointing at the old instance (e.g. a refresh that landed while
    /// the view was offscreen).
    private func scheduleStaleCheck() {
        staleCheckTask?.cancel()

        guard let id = vm.detailID,
              let pair = vm.pairs.first(where: { $0.id == id }) else { return }
        let url = pair.imageURL
        let capturedID = id
        let imageCache = vm.imageCache

        staleCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled, vm.detailID == capturedID else { return }

            guard let entry = await imageCache.entry(for: url) else { return }
            guard !Task.isCancelled, vm.detailID == capturedID else { return }

            // Swap only if the cache holds a different version than what's
            // on screen. Use mtime as the version identity; fall back to
            // instance identity when no mtime is recorded.
            let isSameVersion: Bool
            if let cachedMtime = entry.mtime, let displayedMtime = loadedImageMtime {
                isSameVersion = cachedMtime == displayedMtime
            } else {
                isSameVersion = entry.image === loadedImage
            }
            guard !isSameVersion else { return }

            loadedImage = entry.image
            loadedImageMtime = entry.mtime
        }
    }
}

// MARK: - Caption Editing

struct CaptionEditingContainer: View {
    @ObservedObject var vm: DatasetViewModel

    @State private var localText: String = ""
    @State private var savedText: String = ""
    @State private var currentID: UUID? = nil

    var body: some View {
        VStack(alignment: .leading) {
            Text("Caption / descrição:")
                .font(.subheadline)
            CaptionEditorView(text: $localText)
                .frame(minHeight: 200)
        }
        .padding()
        .onChange(of: localText) {
            vm.liveEditingText = localText
            vm.setEditingDirty(localText != savedText)
        }
        .onChange(of: vm.detailID) {
            flushAndSync()
        }
        .onChange(of: vm.captionReloadToken) {
            syncFromVM()
        }
        .onAppear {
            syncFromVM()
        }
    }

    private func flushAndSync() {
        if let oldID = currentID,
           let idx = vm.pairs.firstIndex(where: { $0.id == oldID }),
           vm.pairs[idx].captionText != localText {
            vm.pairs[idx].captionText = localText
        }
        syncFromVM()
    }

    private func syncFromVM() {
        guard let id = vm.detailID,
              let pair = vm.pairs.first(where: { $0.id == id }) else {
            localText = ""
            savedText = ""
            currentID = nil
            vm.setEditingDirty(false)
            return
        }
        localText = pair.captionText
        savedText = pair.savedCaptionText
        currentID = id
        vm.liveEditingText = localText
        vm.setEditingDirty(localText != savedText)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
