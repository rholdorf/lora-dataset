# Phase 7: NSTextView Caption Editor - Context

**Gathered:** 2026-03-15
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace SwiftUI's `TextEditor` with a native `NSTextView` (via `NSViewRepresentable`) to provide spell checking, grammar checking, dictionary lookup, and LoRA-safe text substitution settings. The editor remains a plain-text caption editor — no rich text or formatting capabilities.

</domain>

<decisions>
## Implementation Decisions

### Auto-correction & substitutions
- Disable auto-correction — spell check underlines errors but nothing gets auto-replaced
- Disable auto-capitalization — LoRA prompts use specific casing conventions
- Disable link detection — URLs stay as plain text, no clickable links
- Disable text replacement — no system substitutions (e.g., (c)→©), what you type is what gets saved
- Disable smart quotes and smart dashes (per EDIT-04) — protects LoRA training data tokens

### Undo & dirty state
- Dirty indicator tracks whether current text differs from last-saved text (undoing all changes back to saved state clears dirty naturally)
- Undo history preserved across saves — Cmd+Z can undo past save points (standard macOS behavior like TextEdit)
- Undo history cleared on image switch — each image gets a fresh undo stack
- No unsaved-changes warning dialog on image switch — silent dirty state, user saves when ready (consistent with current app behavior)

### Claude's Discretion
- Editor font, size, and line spacing
- Border and background styling (current TextEditor has a rounded rectangle stroke overlay)
- Internal padding/margins within the NSTextView
- How text changes sync back to the ViewModel binding

</decisions>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches. The key principle is "LoRA-safe by default": every text substitution or auto-modification feature that could silently alter training data tokens should be disabled.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ZoomablePannableImage` (`ZoomablePannableImage.swift`): Established `NSViewRepresentable` + coordinator pattern for wrapping AppKit views. Same architecture applies to the NSTextView wrapper.
- `ImageCaptionPair` (`ImageCaptionPair.swift`): `captionText` / `savedCaptionText` comparison drives the dirty indicator. NSTextView must update `captionText` on text changes.

### Established Patterns
- `NSViewRepresentable` with coordinator for bidirectional state sync (scale/offset in ZoomablePannableImage)
- `isUpdatingProgrammatically` flag to prevent feedback loops during state sync
- `Binding(get:set:)` pattern for caption text at `ContentView.swift:245-248`
- Dirty state via `captionText != savedCaptionText` in `ImageCaptionPair`

### Integration Points
- `ContentView.swift:245-248`: Current `TextEditor` to be replaced with new `NSTextView` wrapper
- `ContentView.swift:242-256`: VStack containing caption label and editor — new view slots in here
- `DatasetViewModel.saveSelected()`: Saves `captionText` to disk — no changes needed, just needs NSTextView to update the model
- `DatasetViewModel.reloadCaption()`: Reloads text from disk into `captionText` — NSTextView must reflect this

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 07-nstextview-caption-editor*
*Context gathered: 2026-03-15*
