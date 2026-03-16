# Phase 8: Finder Context Menus - Context

**Gathered:** 2026-03-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Add right-click context menus to sidebar file and folder rows. File menus include Reveal in Finder, Open With (submenu), and Quick Look. Folder menus include Open in Finder and Open in Terminal. No caption file actions — captions are edited in-app.

</domain>

<decisions>
## Implementation Decisions

### File context menu
- Context menu targets the image file only — no caption file actions
- Same menu for all file rows regardless of caption state or selection state
- "Reveal in Finder" uses `NSWorkspace.shared.activateFileViewerSelecting([url])` to select the image file in Finder

### Folder context menu
- "Open in Finder" opens the folder in a Finder window
- "Open in Terminal" opens Terminal.app at the folder path

### Open With submenu
- Full app list populated via `NSWorkspace.urlsForApplications(toOpen:)` for the image file type
- Each app shows its icon (fetched via `NSWorkspace.shared.icon(forFile:)`)
- Default app shown first with bold text, remaining apps listed alphabetically
- "Other..." item at bottom separated by a divider — opens NSOpenPanel filtered to .app bundles

### Quick Look
- Use `QLPreviewPanel.shared()` toggle with minimal data source setup
- Keep it lightweight — Phase 9 will build the full QLPreviewPanel infrastructure with spacebar support and may refactor
- Quick Look always available on any file row (not disabled for currently-selected file)
- Previews the image file only, not the caption file

### Claude's Discretion
- Menu item ordering and divider placement within the context menu
- Whether to use SwiftUI `.contextMenu` or NSMenu for implementation
- Menu item icons (SF Symbols or none)
- How to handle the QLPreviewPanel data source minimally

</decisions>

<specifics>
## Specific Ideas

- Finder-native feel: "Open With" should look and behave like Finder's own Open With submenu (bold default app, icons, alphabetical order, "Other..." at bottom)
- "Open in Terminal" on folders is a developer-oriented convenience for working with dataset directories

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `FileNode` (`FileNode.swift`): Has `url: URL` property for folder operations (Open in Finder, Open in Terminal)
- `ImageCaptionPair` (`ImageCaptionPair.swift`): Has `imageURL` for file operations (Reveal in Finder, Open With, Quick Look)
- `FolderNodeView` (`ContentView.swift:169-206`): Folder row view where folder context menu attaches
- File rows (`ContentView.swift:28-46`): `ForEach(vm.pairs)` where file context menu attaches

### Established Patterns
- `onTapGesture` used on folder nodes for navigation — context menu must coexist without conflict
- Manual disclosure chevrons separate from folder label interaction
- Flat file structure — new views go in `lora-dataset/lora-dataset/`

### Integration Points
- File rows in `ContentView.swift:28-46`: Attach `.contextMenu` modifier to the `HStack` inside `ForEach`
- `FolderNodeView` body (`ContentView.swift:181-205`): Attach `.contextMenu` to the outer `HStack`
- `NSWorkspace.shared` for Reveal in Finder, Open With, and Open in Terminal operations
- `QLPreviewPanel` for Quick Look — needs minimal data source conformance

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 08-finder-context-menus*
*Context gathered: 2026-03-15*
