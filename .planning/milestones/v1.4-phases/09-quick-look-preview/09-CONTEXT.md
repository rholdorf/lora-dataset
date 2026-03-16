# Phase 9: Quick Look Preview - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire spacebar and context menu to open the native floating QLPreviewPanel for the selected image. Panel follows selection changes and dismisses on spacebar/Escape. Refactor Phase 8's minimal QL infrastructure into a proper QLPreviewPanel pattern.

</domain>

<decisions>
## Implementation Decisions

### Spacebar key capture
- Use SwiftUI `.onKeyPress` (macOS 14+) — bumping minimum deployment target to macOS 14 is acceptable
- Spacebar active in sidebar and image pane, but NOT in the caption editor (where it types a space)
- When QL panel is visible, spacebar dismisses it regardless of focus (universal toggle)
- Escape also dismisses the QL panel (per QLPV-02)
- Spacebar does nothing when no image file is selected (e.g., folder selected or no selection)

### Panel follows selection
- QL panel auto-updates to show newly selected image when selection changes (matches Finder behavior)
- Arrow key navigation in sidebar updates the QL panel automatically
- Panel closes when user navigates to a different folder (selection clears = panel closes)

### Panel architecture
- Manual `QLPreviewPanel.shared()` via AppKit — no SwiftUI `.quickLookPreview` modifier (avoids sheet-vs-floating-panel risk per STATE.md blocker)
- Refactor into proper `QLPreviewPanelDelegate` + `QLPreviewPanelDataSource` pattern, replacing Phase 8's minimal `QLPreviewHelper`
- Delete `QLPreviewHelper.swift` — build new QL infrastructure as a dedicated controller or directly on ViewModel
- Unify context menu "Quick Look" and spacebar into the same code path — one QL infrastructure for both entry points

### Claude's Discretion
- Whether QL delegate/data source lives on ViewModel or a separate controller class
- How to detect caption editor focus for spacebar suppression
- NSResponder chain setup for proper QLPreviewPanel delegate forwarding
- Animation/transition behavior when panel updates to a new image

</decisions>

<specifics>
## Specific Ideas

- Should behave like Finder's Quick Look: spacebar toggles, arrows cycle, selection-following is automatic
- Universal dismiss: spacebar closes the panel even if caption editor has focus (Finder-like override)

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `QLPreviewHelper` (`QLPreviewHelper.swift`): Minimal data source — will be deleted and replaced with proper pattern
- `quickLook(url:)` (`DatasetViewModel.swift:364-378`): Existing toggle logic — will be refactored into unified QL infrastructure
- `NSApp.keyWindow?.makeFirstResponder(nil)` pattern: Established workaround for NSTextView hijacking QLPreviewPanel

### Established Patterns
- `NSViewRepresentable` + coordinator for AppKit integration (ZoomablePannableImage, CaptionEditorView)
- ViewModel as central state manager (`@MainActor class DatasetViewModel`)
- `selectedID` drives current selection — QL panel can observe this for follow-selection behavior

### Integration Points
- Context menu "Quick Look" action (`ContentView.swift:59`): Currently calls `vm.quickLook(url:)` — will call unified method
- `selectedID` changes (`DatasetViewModel`): QL panel should react to selection changes when visible
- Folder navigation: When `loadDirectory()` fires, QL panel should close

</code_context>

<deferred>
## Deferred Ideas

- Batch Quick Look cycling through multiple selected images (QLPV-04 in future requirements)

</deferred>

---

*Phase: 09-quick-look-preview*
*Context gathered: 2026-03-16*
