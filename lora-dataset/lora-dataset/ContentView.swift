import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var vm = DatasetViewModel()
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var loadedImage: NSImage? = nil
    @State private var selectedFileID: UUID? = nil

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
                                    if pair.isDirty {
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
            DetailView(vm: vm, loadedImage: $loadedImage, imageScale: $imageScale, imageOffset: $imageOffset)
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

        guard let id = selectedFileID,
              let pair = vm.pairs.first(where: { $0.id == id }) else {
            loadedImage = nil
            return
        }

        loadedImage = NSImage(contentsOf: pair.imageURL)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedID = vm.selectedID,
               let idx = vm.pairs.firstIndex(where: { $0.id == selectedID }) {
                // Caption header
                Text(vm.pairs[idx].captionURL.lastPathComponent)
                    .font(.headline)

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
                        CaptionEditorView(text: Binding(
                            get: { vm.pairs[idx].captionText },
                            set: { vm.pairs[idx].captionText = $0 }
                        ))
                        .frame(minHeight: 200)
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
