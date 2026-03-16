# Phase 1: Directory Tree Navigation - Research

**Researched:** 2025-12-20
**Domain:** SwiftUI hierarchical list/tree views for macOS sidebar navigation
**Confidence:** HIGH

<research_summary>
## Summary

Researched SwiftUI approaches for implementing a Finder-like folder tree sidebar on macOS 14+. The standard approach uses SwiftUI's `List` with the `children:` parameter for hierarchical data, combined with `NavigationSplitView` for the sidebar/detail layout.

**Critical finding:** SwiftUI's native `OutlineGroup` has known bugs on macOS with dynamic content that cause crashes and incorrect cell updates. However, using `List(data, children: \.children)` directly is more stable and is the recommended approach for macOS 14+.

**Security-scoped bookmarks:** When user selects a parent directory, subdirectories within it are automatically accessible - no new bookmarks needed for child folders. This simplifies the implementation significantly.

**Primary recommendation:** Use native SwiftUI `List` with `children:` parameter and `SidebarListStyle`. Model folders as a recursive tree structure with lazy-loading of children to avoid scanning deep hierarchies upfront. Leverage existing security-scoped bookmark which already grants access to the selected folder's subdirectories.
</research_summary>

<standard_stack>
## Standard Stack

### Core (Already in Project)
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| SwiftUI List with children | macOS 14+ | Hierarchical sidebar | Native, stable, integrates with NavigationSplitView |
| NavigationSplitView | macOS 13+ | Sidebar/detail layout | Already used in current app |
| FileManager | Foundation | Directory enumeration | Standard API for file system access |
| Security-scoped bookmarks | Foundation | Persistent folder access | Already implemented in app |

### Supporting (No New Dependencies)
| Component | Purpose | When to Use |
|-----------|---------|-------------|
| DisclosureGroup | Programmatic expand control | If need to persist expansion state |
| @SceneStorage | Persist expansion state | Store which folders are expanded |
| DirectoryEnumerator | Lazy file iteration | Avoid loading entire tree upfront |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| List with children | OutlineGroup | OutlineGroup has bugs with dynamic content on macOS |
| List with children | OutlineView (3rd party) | Requires NSView cells, more complex |
| List with children | ProjectNavigator (3rd party) | Over-engineered for this use case |
| Recursive scan upfront | Lazy loading | Upfront scan kills performance on deep trees |

**Installation:**
No new dependencies needed - pure SwiftUI/AppKit.
</standard_stack>

<architecture_patterns>
## Architecture Patterns

### Recommended Project Structure
```
lora-dataset/
├── Models/
│   ├── ImageCaptionPair.swift     # Existing
│   └── FileNode.swift             # NEW: Tree node for folder hierarchy
├── ViewModels/
│   └── DatasetViewModel.swift     # Extend with folder tree state
└── Views/
    ├── ContentView.swift          # Update sidebar to use folder tree
    └── FolderTreeView.swift       # NEW: Recursive folder tree component
```

### Pattern 1: Recursive File Node Model
**What:** Tree-structured data model representing folders and files
**When to use:** Any hierarchical file display

```swift
struct FileNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?  // nil = not loaded, [] = empty folder, [items] = loaded

    var icon: String {
        if isDirectory {
            return children?.isEmpty == false ? "folder.fill" : "folder"
        }
        return "doc"
    }
}
```

### Pattern 2: List with Children for Sidebar
**What:** SwiftUI's built-in hierarchical list
**When to use:** Displaying tree structures in sidebars

```swift
List(selection: $selectedFolder) {
    ForEach(rootNodes) { node in
        if node.isDirectory {
            // Recursive tree using List's children parameter
            Label(node.name, systemImage: node.icon)
                .tag(node.id)
        }
    }
}
.listStyle(.sidebar)
```

OR using the simpler children parameter:

```swift
List(rootNodes, children: \.children, selection: $selectedFolder) { node in
    Label(node.name, systemImage: node.icon)
}
.listStyle(.sidebar)
```

### Pattern 3: Lazy Loading Children on Expand
**What:** Load folder contents only when user expands
**When to use:** Deep folder hierarchies

```swift
// Model with lazy-loaded children
class FolderNode: ObservableObject, Identifiable {
    let url: URL
    @Published var children: [FolderNode]? = nil
    @Published var isLoading = false

    func loadChildrenIfNeeded() {
        guard children == nil, !isLoading else { return }
        isLoading = true
        // Load children asynchronously
        Task {
            children = await scanDirectoryForFolders(url)
            isLoading = false
        }
    }
}
```

### Anti-Patterns to Avoid
- **Scanning entire tree upfront:** Load only visible level, expand on demand
- **Using OutlineGroup directly:** Has bugs with dynamic content on macOS
- **Creating new bookmarks for subdirectories:** Parent bookmark covers children
- **Storing full file list in tree nodes:** Only store folders in tree, files in detail view
</architecture_patterns>

<dont_hand_roll>
## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Recursive tree view | Custom nested ForEach | `List(data, children: \.children)` | SwiftUI handles expand/collapse, indentation, disclosure arrows |
| Directory enumeration | Recursive function scanning all subdirs | `FileManager.enumerator()` with skip options | Performance - lazy iterator vs loading all |
| Folder icons | Custom icon logic | SF Symbols (`folder`, `folder.fill`, `doc`) | Native look, automatic dark mode support |
| Expand/collapse state | Manual @State per folder | DisclosureGroup with Set<UUID> | Clean persistence with @SceneStorage |
| Subdirectory access | New bookmarks for each folder | Parent security-scoped bookmark | Subdirs automatically accessible under parent |

**Key insight:** SwiftUI's `List` with `children:` parameter does most of the heavy lifting. The complexity is in the data model and lazy loading, not the view layer.
</dont_hand_roll>

<common_pitfalls>
## Common Pitfalls

### Pitfall 1: Loading Entire File Tree Upfront
**What goes wrong:** App freezes or crashes when opening folder with deep hierarchy
**Why it happens:** Recursive scan of entire file system before displaying anything
**How to avoid:** Load only immediate children of expanded folders; use nil children to indicate "not loaded"
**Warning signs:** Slow startup, memory spikes when selecting folders

### Pitfall 2: OutlineGroup Crashes on macOS
**What goes wrong:** App crashes when scrolling or updating list with OutlineGroup
**Why it happens:** SwiftUI OutlineGroup has bugs with dynamic content on macOS causing invalid index access
**How to avoid:** Use `List(data, children: \.children)` instead of OutlineGroup
**Warning signs:** "Row index out of range" crashes, incorrect cell rendering

### Pitfall 3: Lazy Loading Not Actually Lazy
**What goes wrong:** SwiftUI calls children getter for all nodes, loading entire tree
**Why it happens:** List evaluates children keypath eagerly in some configurations
**How to avoid:** Use class-based nodes with @Published children; load in .onAppear or expand action
**Warning signs:** All folders loading even when collapsed

### Pitfall 4: Security Scope Lost When Navigating
**What goes wrong:** "Operation not permitted" when accessing files in subfolders
**Why it happens:** Not using the resolved security-scoped URL, or stopping access too early
**How to avoid:** Always use the URL from resolved bookmark; subdirs are covered by parent bookmark
**Warning signs:** Can access parent folder but not children

### Pitfall 5: Forgetting to Update File List When Folder Selected
**What goes wrong:** Detail view shows old folder's files after selecting new folder
**Why it happens:** Only tree selection updated, not the pairs array
**How to avoid:** Observe selectedFolder changes, trigger scanDirectory for new folder
**Warning signs:** UI shows stale data, confusion about which folder is active
</common_pitfalls>

<code_examples>
## Code Examples

### FileNode Model
```swift
// Source: Adapted from SwiftUI Recipes and Apple docs
struct FileNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var children: [FileNode]?

    var name: String { url.lastPathComponent }
    var isDirectory: Bool { children != nil }

    var icon: String {
        if children == nil { return "doc" }
        return children?.isEmpty == true ? "folder" : "folder.fill"
    }
}
```

### Building Tree from Directory
```swift
// Source: FileManager docs + community patterns
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
```

### Sidebar with Folder Tree
```swift
// Source: SwiftUI List docs + sidebar patterns
NavigationSplitView {
    List(selection: $selectedFolderID) {
        Section("Folders") {
            ForEach(folderTree) { node in
                FolderRow(node: node)
            }
        }
    }
    .listStyle(.sidebar)
} detail: {
    // Image/caption detail view
}

// Where FolderRow handles recursion:
struct FolderRow: View {
    let node: FileNode

    var body: some View {
        if let children = node.children, !children.isEmpty {
            DisclosureGroup {
                ForEach(children) { child in
                    FolderRow(node: child)
                }
            } label: {
                Label(node.name, systemImage: node.icon)
            }
        } else {
            Label(node.name, systemImage: node.icon)
        }
    }
}
```

### Simpler Approach with List children parameter
```swift
// Source: Apple List documentation
List(folderTree, children: \.children, selection: $selectedFolderID) { node in
    Label(node.name, systemImage: node.icon)
        .tag(node.id)
}
.listStyle(.sidebar)
```
</code_examples>

<sota_updates>
## State of the Art (2024-2025)

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| OutlineGroup in List | List with children parameter | iOS 14+ / macOS 11+ | More stable, especially on macOS |
| @StateObject ViewModel | @Observable class | macOS 14 / iOS 17 | Simpler observation, better performance |
| NavigationView | NavigationSplitView | macOS 13 / iOS 16 | Already using this in current app |
| Imperative expand control | DisclosureGroup binding | iOS 14+ | Cleaner API for state persistence |

**New tools/patterns to consider:**
- **@Observable macro (macOS 14+):** Simpler than @Published, automatic dependency tracking
- **SceneStorage for expansion state:** Persist which folders are expanded across launches

**Deprecated/outdated:**
- **NavigationView:** Replaced by NavigationSplitView (already updated in this app)
- **Direct OutlineGroup use on macOS:** Buggy with dynamic content, use List with children
</sota_updates>

<open_questions>
## Open Questions

1. **Expansion State Persistence**
   - What we know: Can use @SceneStorage with Set<UUID> to store expanded folder IDs
   - What's unclear: Should we persist across launches or start fresh?
   - Recommendation: Start with fresh (collapsed) state; add persistence if user requests

2. **Root Folder Selection**
   - What we know: User currently selects folder via NSOpenPanel
   - What's unclear: Should tree show parent of selected folder? Or only children?
   - Recommendation: Show selected folder as root + its children; "Choose Folder" button to change root

3. **Handling Very Deep Hierarchies**
   - What we know: Lazy loading prevents loading everything upfront
   - What's unclear: What's the performance cliff? 1000 folders? 10000?
   - Recommendation: Test with large hierarchies; consider virtual scrolling if needed (unlikely for typical datasets)
</open_questions>

<sources>
## Sources

### Primary (HIGH confidence)
- [Apple OutlineGroup Documentation](https://developer.apple.com/documentation/swiftui/outlinegroup) - API reference
- [Apple FileManager.DirectoryEnumerator](https://developer.apple.com/documentation/foundation/filemanager/directoryenumerator) - Lazy enumeration
- [SwiftLee: Security-scoped bookmarks](https://www.avanderlee.com/swift/security-scoped-bookmarks-for-url-access/) - Subdirectory access confirmation

### Secondary (MEDIUM confidence)
- [Swift with Majid: OutlineGroup](https://swiftwithmajid.com/2020/09/02/displaying-recursive-data-using-outlinegroup-in-swiftui/) - Patterns verified against Apple docs
- [SwiftUI Recipes: File Tree](https://swiftuirecipes.com/blog/file-tree-with-expanding-list-in-swiftui) - List with children pattern
- [TrozWare: SwiftUI for Mac 2024](https://troz.net/post/2024/swiftui-mac-2024/) - macOS-specific updates

### Tertiary (LOW confidence - needs validation)
- [OutlineView package](https://github.com/Sameesunkaria/OutlineView) - Alternative if native approach fails
- [Apple Forums: OutlineGroup bugs](https://developer.apple.com/forums/thread/662937) - Bug reports, monitor for fixes
</sources>

<metadata>
## Metadata

**Research scope:**
- Core technology: SwiftUI List, NavigationSplitView, FileManager
- Ecosystem: No external dependencies (pure SwiftUI/AppKit)
- Patterns: Recursive tree model, lazy loading, sidebar navigation
- Pitfalls: OutlineGroup bugs, eager loading, security scope handling

**Confidence breakdown:**
- Standard stack: HIGH - Native SwiftUI, already partially implemented
- Architecture: HIGH - Verified patterns from Apple docs and community
- Pitfalls: HIGH - Documented bugs with workarounds
- Code examples: HIGH - Adapted from official docs and verified tutorials

**Research date:** 2025-12-20
**Valid until:** 2026-01-20 (30 days - SwiftUI macOS stable)
</metadata>

---

*Phase: 01-directory-tree-navigation*
*Research completed: 2025-12-20*
*Ready for planning: yes*
