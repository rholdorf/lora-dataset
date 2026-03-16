import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var vm = DatasetViewModel()
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var loadedImage: NSImage? = nil
    @State private var selectedFileID: UUID? = nil
    @State private var showSpinner: Bool = false
    @State private var loadError: Bool = false
    @State private var loadErrorFilename: String = ""

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Divider()

                // Sidebar with folders and files
                ScrollViewReader { proxy in
                    List(selection: $selectedFileID) {
                        // Folders section - using recursive DisclosureGroup for expansion control
                        if !vm.folderTree.isEmpty {
                            Section("Pastas") {
                                FolderTreeView(nodes: vm.folderTree, vm: vm)
                            }
                        }

                        // Files section
                        Section("Arquivos (\(vm.pairs.count))") {
                            ForEach(vm.pairs) { pair in
                                HStack(spacing: 4) {
                                    Text(pair.imageURL.lastPathComponent)
                                    if pair.isDirty || (pair.id == vm.selectedID && vm.editingIsDirty) {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundColor(.orange)
                                    }
                                    Spacer()
                                    if pair.captionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("sem caption")
                                            .font(.caption)
                                            .italic()
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .tag(pair.id)
                                .id(pair.id)
                                .contextMenu {
                                    Button {
                                        vm.revealInFinder(url: pair.imageURL)
                                    } label: {
                                        Label("Reveal in Finder", systemImage: "folder.badge.magnifyingglass")
                                    }

                                    openWithMenu(for: pair.imageURL)

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
                        // Scroll to selected item when pairs are loaded (session restore)
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
        } detail: {
            DetailView(
                vm: vm,
                loadedImage: $loadedImage,
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
                .disabled(vm.selectedID == nil)

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
        .onAppear {
            selectedFileID = vm.selectedID
            loadImageForSelection()
        }
        .onChange(of: selectedFileID) {
            // Sync local selection to ViewModel
            Task { @MainActor in
                vm.selectedID = selectedFileID
                loadImageForSelection()
            }
        }
        .onChange(of: vm.selectedID) {
            // Sync ViewModel selection to local (e.g., after folder navigation)
            Task { @MainActor in
                if selectedFileID != vm.selectedID {
                    selectedFileID = vm.selectedID
                }
            }
        }
        .onChange(of: vm.pairs) {
            // When pairs change, sync selection
            Task { @MainActor in
                selectedFileID = vm.selectedID
                loadImageForSelection()
            }
        }
    }

    private func loadImageForSelection() {
        imageScale = 1.0
        imageOffset = .zero
        showSpinner = false
        loadError = false

        guard let id = selectedFileID,
              let pair = vm.pairs.first(where: { $0.id == id }) else {
            loadedImage = nil
            return
        }

        let url = pair.imageURL
        let capturedID = id

        Task { @MainActor in
            // Fast path: cache hit
            if let cached = await vm.imageCache.image(for: url) {
                guard self.selectedFileID == capturedID else { return }
                self.loadedImage = cached
                print("[cache] hit for \(url.lastPathComponent)")
                // Trigger prefetch for neighbors
                vm.triggerPrefetch(aroundID: capturedID)
                return
            }

            print("[cache] miss for \(url.lastPathComponent)")

            // Slow path: cache miss -- start 150ms delayed spinner
            let spinnerTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard self.selectedFileID == capturedID, self.loadedImage == nil else { return }
                self.showSpinner = true
            }

            // Load off-main-thread at display size (800 = 2x retina of 400pt frame)
            let result = await Task.detached(priority: .userInitiated) {
                loadImage(url: url, maxPixelSize: 800)
            }.value

            spinnerTask.cancel()
            guard self.selectedFileID == capturedID else { return }
            self.showSpinner = false

            if let img = result {
                self.loadedImage = img
                self.loadError = false
                // Insert into cache for future hits
                let cost = img.representations.first.map { $0.pixelsWide * $0.pixelsHigh * 4 }
                    ?? Int(img.size.width * img.size.height * 4)
                await vm.imageCache.insert(img, cost: cost, for: url)
                // Trigger prefetch for neighbors
                vm.triggerPrefetch(aroundID: capturedID)
            } else {
                // Load failure: show error state (per user decision)
                self.loadedImage = nil
                self.loadError = true
                self.loadErrorFilename = url.lastPathComponent
            }
        }
    }

    @ViewBuilder
    private func openWithMenu(for fileURL: URL) -> some View {
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

// Recursive folder tree view with manual disclosure (not DisclosureGroup)
// This separates the disclosure toggle from folder navigation
struct FolderTreeView: View {
    let nodes: [FileNode]
    @ObservedObject var vm: DatasetViewModel

    var body: some View {
        ForEach(nodes) { node in
            FolderNodeView(node: node, vm: vm)

            // Children (if expanded)
            if let children = node.children, !children.isEmpty, vm.isExpanded(path: node.url.path) {
                FolderTreeView(nodes: children, vm: vm)
                    .padding(.leading, 16)
            }
        }
    }
}

// Individual folder node - separate view to ensure proper state updates
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
            // Disclosure chevron (only for folders with children)
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

            // Folder label - navigation via tap gesture on the whole area
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

// Detail view for image and caption editing
struct DetailView: View {
    @ObservedObject var vm: DatasetViewModel
    @Binding var loadedImage: NSImage?
    @Binding var imageScale: CGFloat
    @Binding var imageOffset: CGSize
    @Binding var showSpinner: Bool
    @Binding var loadError: Bool
    @Binding var loadErrorFilename: String

    @State private var captionFilename: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if vm.selectedID != nil {
                Text(captionFilename)
                    .font(.headline)

                HSplitView {
                    Group {
                        if loadError {
                            // Error state: warning icon + filename (per user decision)
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
                                offset: $imageOffset
                            )
                            .frame(width: 400, height: 400)
                            .clipped()
                            .overlay {
                                if showSpinner {
                                    // Spinner on dimmed previous image (per user decision)
                                    ZStack {
                                        Color.black.opacity(0.3)
                                        ProgressView()
                                            .controlSize(.large)
                                    }
                                }
                            }
                        } else if showSpinner {
                            // No previous image yet, but spinner should show
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

                    // Caption editing in its own view — isolates @State so
                    // keystrokes only re-render the editor, not the image panel.
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
        .onChange(of: vm.selectedID) {
            syncCaptionFilename()
        }
        .onAppear {
            syncCaptionFilename()
        }
    }

    private func syncCaptionFilename() {
        guard let id = vm.selectedID,
              let pair = vm.pairs.first(where: { $0.id == id }) else {
            captionFilename = ""
            return
        }
        captionFilename = pair.captionURL.lastPathComponent
    }
}

// Isolates caption editing state so that per-keystroke @State changes
// only invalidate this view, NOT the parent DetailView (which contains
// the expensive ZoomablePannableImage).
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
            // Non-published write — does NOT fire objectWillChange
            vm.liveEditingText = localText
            // Only fires objectWillChange on actual state transitions
            // (false→true on first keystroke, NOT on every keystroke)
            vm.setEditingDirty(localText != savedText)
        }
        .onChange(of: vm.selectedID) {
            flushAndSync()
        }
        .onChange(of: vm.captionReloadToken) {
            syncFromVM()
        }
        .onAppear {
            syncFromVM()
        }
    }

    /// Flush current edits to pairs before loading new selection.
    private func flushAndSync() {
        if let oldID = currentID,
           let idx = vm.pairs.firstIndex(where: { $0.id == oldID }),
           vm.pairs[idx].captionText != localText {
            vm.pairs[idx].captionText = localText
        }
        syncFromVM()
    }

    private func syncFromVM() {
        guard let id = vm.selectedID,
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
