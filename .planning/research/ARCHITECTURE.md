# Architecture Research

**Domain:** Native macOS OS Integration — SwiftUI + AppKit hybrid app
**Researched:** 2026-03-15
**Confidence:** HIGH (all three integration areas verified against Apple docs and community implementation patterns)

## Context: What Already Exists

The app is a SwiftUI + AppKit hybrid using the NSViewRepresentable pattern:

```
ContentView (SwiftUI)
  NavigationSplitView
    ├── Sidebar (SwiftUI List)
    │     ├── FolderTreeView / FolderNodeView (SwiftUI)
    │     └── File rows (ForEach over vm.pairs)
    └── DetailView (SwiftUI)
          ├── ZoomablePannableImage (NSViewRepresentable → ZoomableImageNSView)
          └── TextEditor (SwiftUI — being replaced)

DatasetViewModel (@MainActor ObservableObject)
  └── @Published pairs, selectedID, folderTree, directoryURL, expandedPaths
```

The coordinator pattern is already established in `ZoomablePannableImage`. The same pattern applies to both new features that require NSView bridging.

---

## System Overview: After v1.4

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SwiftUI Layer                                 │
├────────────────────────┬────────────────────────────────────────────┤
│      Sidebar           │              DetailView                     │
│  FolderNodeView        │  ZoomablePannableImage  │  NativeTextEditor │
│  .contextMenu()        │  (existing NSViewRep)   │  (new NSViewRep)  │
│  FileRow               │                         │                   │
│  .contextMenu()        ├─────────────────────────┴───────────────────┤
│                        │       .quickLookPreview($previewURL)        │
├────────────────────────┴─────────────────────────────────────────────┤
│                        AppKit Layer                                  │
│  NSMenu (auto via     │  ZoomableImageNSView  │  NSTextView          │
│  .contextMenu)         │  (existing)           │  (new)               │
│                        │                       │  NSScrollView wrap   │
│                        │  QLPreviewPanel        │                      │
│                        │  (managed by SwiftUI   │                      │
│                        │   .quickLookPreview)   │                      │
├────────────────────────┴───────────────────────┴─────────────────────┤
│                    DatasetViewModel (@MainActor)                      │
│    pairs, selectedID, directoryURL — no new published state needed   │
│    + previewURL: URL? (drives quickLookPreview binding)              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

| Component | Status | Responsibility |
|-----------|--------|----------------|
| `ContentView` | Modify | Add `.quickLookPreview` modifier; wire keyboard shortcut for spacebar |
| `FolderNodeView` | Modify | Add `.contextMenu` modifier with folder actions |
| File row in sidebar `ForEach` | Modify | Add `.contextMenu` modifier with file actions |
| `DetailView` | Modify | Replace `TextEditor` with `NativeTextEditor` |
| `NativeTextEditor` | New | `NSViewRepresentable` wrapping `NSScrollView + NSTextView` |
| `DatasetViewModel` | Modify | Add `previewURL: URL?` published property |

No new view model is needed. No new coordinator pattern — re-use the established `NSViewRepresentable + Coordinator` approach from `ZoomablePannableImage`.

---

## Feature 1: Finder Context Menus

### Integration Approach

Use SwiftUI's native `.contextMenu` modifier — not raw `NSMenu`. SwiftUI internally creates the `NSMenu` for you on macOS. The native `.contextMenu` modifier is the correct approach for this codebase; reaching down to AppKit for menus would add complexity with no benefit.

**Two surfaces need context menus:**

**A. Folder rows** (`FolderNodeView`):
```swift
// In FolderNodeView.body, attach to the outer HStack
.contextMenu {
    Button("Reveal in Finder") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: node.url.path) }
    Button("Open in Terminal") { /* open Terminal at node.url */ }
    Button("New Folder Here") { /* call vm method */ }
}
```

**B. File rows** (the `ForEach` in `ContentView`'s sidebar):
```swift
// On the row HStack inside ForEach
.contextMenu {
    Button("Reveal in Finder") { NSWorkspace.shared.selectFile(pair.imageURL.path, inFileViewerRootedAtPath: "") }
    Button("Quick Look") { vm.previewURL = pair.imageURL }
    Button("Copy Path") { NSPasteboard.general.setString(pair.imageURL.path, forType: .string) }
    Divider()
    Button("Delete Caption", role: .destructive) { /* vm method */ }
}
```

### Click Area Fix (Known Pitfall)

SwiftUI's `.contextMenu` on List rows only activates on the text portion by default, not the full row width. Fix by ensuring rows use `.frame(maxWidth: .infinity, alignment: .leading)` and `.contentShape(Rectangle())`:

```swift
HStack(spacing: 4) { ... }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .contextMenu { ... }
```

### What Changes

| File | Change |
|------|--------|
| `ContentView.swift` | Add `.contextMenu` to file row `HStack` inside `ForEach` |
| `ContentView.swift` | Add `.contextMenu` to `FolderNodeView.body` outer `HStack` |
| `DatasetViewModel.swift` | Add action methods called by menu items (e.g., `revealInFinder`, `deleteCaption`) |

No new files needed for context menus.

---

## Feature 2: Quick Look Preview

### Integration Approach

Use SwiftUI's `.quickLookPreview($url)` modifier (available macOS 13+, HIGH confidence). This is the correct modern approach — it handles `QLPreviewPanel` lifecycle automatically and avoids the complexity of manually managing the panel and responder chain.

**Data flow:**
```
User triggers (spacebar / context menu)
    ↓
vm.previewURL = pair.imageURL  (or nil to dismiss)
    ↓
.quickLookPreview($vm.previewURL) modifier observes the binding
    ↓
SwiftUI drives QLPreviewPanel open/close
```

### Keyboard Shortcut (Spacebar)

SwiftUI's `.keyboardShortcut` cannot use bare spacebar (it defaults to ⌘ modifier). Use `.onKeyPress(.space)` (available macOS 14+) or attach the spacebar to a hidden Button with the shortcut — but the simplest approach is to add a `Button` to a `Commands` group or use `.focusedValue` to invoke the toggle.

Recommended: Use a focusable view with `.onKeyPress`:
```swift
// On the List or a wrapper that can receive focus
.onKeyPress(.space) {
    if let pair = vm.selectedPair {
        vm.previewURL = (vm.previewURL == nil) ? pair.imageURL : nil
    }
    return .handled
}
```

This requires the sidebar List to be focusable (it is by default in macOS sidebar context).

### NSTextView Conflict (Critical Pitfall)

`NSTextView` has a private `quickLookPreviewableItemsInRanges:` method that intercepts the `QLPreviewPanel` responder chain while an NSTextView has focus. This means the panel may appear empty or fail to activate when focus is in the text editor.

**Resolution:** The `.quickLookPreview` modifier approach mitigates most of this, but if using a custom `NSTextView` (see Feature 3), the spacebar shortcut must be intercepted before the text view's keyDown handler gets it — or invoke the toggle via a SwiftUI mechanism that bypasses NSTextView's key handling. Since the spacebar is most naturally triggered from the sidebar (file list), not the text editor, this conflict is avoided by design: make the action available only when the sidebar is focused.

### What Changes

| File | Change |
|------|--------|
| `DatasetViewModel.swift` | Add `@Published var previewURL: URL? = nil` |
| `ContentView.swift` | Add `.quickLookPreview($vm.previewURL)` to `NavigationSplitView` or `ContentView` body |
| `ContentView.swift` | Add `.onKeyPress(.space)` to sidebar area |

No new files needed for Quick Look.

---

## Feature 3: Native NSTextView for Caption Editing

### Integration Approach

Replace `TextEditor` in `DetailView` with a new `NativeTextEditor: NSViewRepresentable` that wraps `NSTextView`. Follow the same coordinator pattern as `ZoomablePannableImage`.

The NSTextView must be embedded in an `NSScrollView` to get scroll bars and proper text container layout — this is standard AppKit practice:

```
NativeTextEditor (NSViewRepresentable)
  └── makeNSView → NSScrollView
                     └── documentView = NSTextView
                                         ├── isContinuousSpellCheckingEnabled = true
                                         ├── isGrammarCheckingEnabled = true
                                         ├── isAutomaticSpellingCorrectionEnabled = true
                                         ├── isAutomaticDashSubstitutionEnabled = false  (LoRA captions don't want smart dashes)
                                         ├── isAutomaticQuoteSubstitutionEnabled = false (same reason)
                                         └── allowsUndo = true
```

### Coordinator Pattern

```swift
class Coordinator: NSObject, NSTextViewDelegate {
    var parent: NativeTextEditor

    func textDidChange(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView else { return }
        // Only update if different — prevents feedback loops
        if parent.text != tv.string {
            parent.text = tv.string
        }
    }
}
```

**Critical:** In `updateNSView`, guard against overwriting the NSTextView's string while the user is typing — check if the value changed externally before setting:

```swift
func updateNSView(_ nsView: NSScrollView, context: Context) {
    guard let tv = nsView.documentView as? NSTextView else { return }
    // Only update from outside if text differs (avoid cursor reset mid-typing)
    if tv.string != text {
        tv.string = text
    }
}
```

This mirrors the `isUpdatingProgrammatically` pattern already used in `ZoomableImageNSView`.

### Undo Manager

NSTextView has built-in undo support. However, SwiftUI's environment undo manager may conflict. Set `textView.allowsUndo = true` and do not pass SwiftUI's `undoManager` — let NSTextView manage its own undo stack. This is standard for NSViewRepresentable text views.

### Binding to ViewModel

The `TextEditor` currently binds via:
```swift
TextEditor(text: Binding(
    get: { vm.pairs[idx].captionText },
    set: { vm.pairs[idx].captionText = $0 }
))
```

`NativeTextEditor` takes the same `Binding<String>`. No ViewModel changes needed.

### What Changes

| File | Change |
|------|--------|
| `NativeTextEditor.swift` | New file — `NSViewRepresentable` wrapping NSScrollView + NSTextView |
| `ContentView.swift` → `DetailView` | Replace `TextEditor(...)` with `NativeTextEditor(text: ...)` |

---

## Data Flow Changes

### New State in DatasetViewModel

```
@Published var previewURL: URL? = nil   // drives .quickLookPreview
```

All other state remains unchanged. Context menus call existing ViewModel methods or call `NSWorkspace` directly from the view (acceptable for pure presentation actions like Reveal in Finder).

### Updated Selection Data Flow

The existing selection → image load flow is unchanged. Quick Look previews the `imageURL` of the selected pair:
```
selectedID changes → loadImageForSelection() → vm.previewURL set by user action (not automatically)
```

Quick Look is an explicit user action, not an automatic side effect of selection. This keeps the data flow clean.

---

## Architectural Patterns

### Pattern 1: NSViewRepresentable + Coordinator (Existing, Extended)

**What:** A SwiftUI struct bridges to an AppKit NSView. A Coordinator class holds delegate references and funnels AppKit callbacks back to SwiftUI bindings.

**When to use:** When AppKit provides capabilities SwiftUI does not (rich text editing, custom drawing, zoom/pan). Already in use for `ZoomablePannableImage`.

**NativeTextEditor follows exactly this pattern.** No deviation.

**Trade-offs:** More boilerplate than TextEditor; gains full NSTextView feature set (spell check, grammar, dictionary lookup, services menu, undo, accessibility).

### Pattern 2: SwiftUI Modifier Wrappers for AppKit Features

**What:** Use SwiftUI modifiers (`.contextMenu`, `.quickLookPreview`) instead of reaching down to AppKit APIs directly.

**When to use:** When Apple provides a SwiftUI-native bridge to an AppKit concept. Prefer this over creating custom NSViewRepresentable wrappers for panel/menu management.

**Trade-offs:** Less control, but far less complexity. The `.quickLookPreview` modifier handles QLPreviewPanel lifecycle, responder chain registration, and panel creation automatically.

### Pattern 3: ViewModel Actions for Menu Items

**What:** Context menu `Button` closures call `DatasetViewModel` methods rather than calling file system APIs directly.

**When to use:** For any action that mutates app state or touches the file system (delete, rename, create). Call `NSWorkspace` directly only for pure OS delegation (Reveal in Finder, Open in Terminal) that does not mutate app state.

---

## Build Order

Dependencies between features determine this order:

```
1. NativeTextEditor (NSViewRepresentable)
   No dependencies on other v1.4 features.
   Self-contained. Replace TextEditor in DetailView.

2. Context Menus
   Depends on: ViewModel having action methods.
   No dependency on NativeTextEditor or Quick Look.
   Add .contextMenu to FolderNodeView and file rows.

3. Quick Look Preview
   Depends on: vm.previewURL property (added in step 2 or standalone).
   Has interaction with NativeTextEditor focus — build last so the
   NSTextView/QLPreviewPanel conflict can be tested and handled.
```

Build NativeTextEditor first because it is purely additive (replaces existing component) and has no interactions with the other two features. Context menus are second because they are also self-contained and establish `vm.previewURL`. Quick Look goes last because it requires testing the spacebar+NSTextView focus interaction.

---

## Integration Points Summary

| New Feature | New Files | Modified Files | ViewModel Changes |
|-------------|-----------|----------------|-------------------|
| Context Menus | None | `ContentView.swift` (2 views) | Add action methods |
| Quick Look | None | `ContentView.swift`, `DatasetViewModel.swift` | Add `previewURL: URL?` |
| NSTextView Editor | `NativeTextEditor.swift` | `ContentView.swift` (DetailView) | None |

Total new files: **1**
Total modified files: **2** (`ContentView.swift`, `DatasetViewModel.swift`)

---

## Anti-Patterns

### Anti-Pattern 1: Manual NSMenu Construction

**What people do:** Create `NSMenu` and `NSMenuItem` instances manually, attach to `NSView.menu`, and manage display manually.

**Why it's wrong:** Bypasses SwiftUI's declarative model. Requires an NSViewRepresentable wrapper just to attach a menu. Loses automatic accessibility, keyboard navigation, and system services integration that `.contextMenu` provides for free.

**Do this instead:** Use `.contextMenu { Button(...) }` on SwiftUI views. SwiftUI translates this to a proper NSMenu internally.

### Anti-Pattern 2: Manual QLPreviewPanel Lifecycle

**What people do:** Implement `QLPreviewPanelDataSource` / `QLPreviewPanelDelegate`, manage `acceptsPreviewPanelControl()`, `beginPreviewPanelControl()`, `endPreviewPanelControl()` — the full legacy AppKit pattern.

**Why it's wrong:** This is 15+ lines of boilerplate dealing with a singleton panel and responder chain traversal. The `.quickLookPreview` modifier handles all of this automatically since macOS 13.

**Do this instead:** Add `@Published var previewURL: URL?` to the ViewModel and `.quickLookPreview($vm.previewURL)` to the view. Done.

### Anti-Pattern 3: Wrapping TextEditor to Fix Spell Check

**What people do:** Access the private NSTextView inside SwiftUI's TextEditor using `introspect` libraries or view hierarchy traversal.

**Why it's wrong:** Fragile — private APIs break without notice. Multiple Apple Developer Forum posts confirm `isContinuousSpellCheckingEnabled` gets reset to `false` unpredictably when set this way.

**Do this instead:** Own the NSTextView directly via NSViewRepresentable. Set properties in `makeNSView` where they are set once and owned by your code.

### Anti-Pattern 4: Updating NSTextView String on Every Render

**What people do:** In `updateNSView`, unconditionally assign `textView.string = text`.

**Why it's wrong:** Resets the cursor position and selection state every time SwiftUI re-renders, which happens frequently. The user's cursor jumps while typing.

**Do this instead:** Guard with `if tv.string != text { tv.string = text }` — only update when the source of truth changed externally (e.g., when user clicks Reload Caption).

---

## Sources

- [SwiftUI contextMenu(forSelectionType:menu:primaryAction:) — SerialCoder.dev](https://serialcoder.dev/text-tutorials/swiftui/enabling-selection-double-click-and-context-menus-in-swiftui-list-on-macos/)
- [NSTextView/QLPreviewPanel responder chain conflict — Michael Berk](https://mberk.com/posts/QuickLook+TextViewTrouble/)
- [QLPreviewPanel responder chain pattern with NSTableView — DevGypsy](https://devgypsy.com/post/2023-06-06-quicklook-swift-tableview/)
- [quickLookPreview SwiftUI modifier — Daniel Saidi](https://danielsaidi.com/blog/2022/06/27/using-quicklook-with-swiftui/)
- [MacEditorTextView NSViewRepresentable reference implementation — unnamedd/GitHub Gist](https://gist.github.com/unnamedd/6e8c3fbc806b8deb60fa65d6b9affab0)
- [NSTextView in SwiftUI coordinator pattern — Blue Lemon Bits](https://bluelemonbits.com/2021/11/14/using-nstextview-in-swiftui/)
- [Context menu click area fix for macOS List — Cocoa Switch](https://www.cocoaswitch.com/2023/12/09/small-click-areas.html)
- [quickLookPreview(_:) — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/view/quicklookpreview(_:))
- [isContinuousSpellCheckingEnabled — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nstextview/iscontinuousspellcheckingenabled)
- [Including Services in contextual menus — Wade Tregaskis](https://wadetregaskis.com/including-services-in-contextual-menus-in-swiftui/)

---
*Architecture research for: LoRA Dataset Browser — v1.4 Native OS Integration*
*Researched: 2026-03-15*
