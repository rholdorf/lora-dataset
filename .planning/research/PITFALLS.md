# Pitfalls Research

**Domain:** Native macOS OS integration — Finder context menus, QLPreviewPanel, NSTextView in sandboxed SwiftUI + AppKit hybrid app
**Researched:** 2026-03-15
**Confidence:** HIGH (responder chain and NSTextView pitfalls well-documented; context menu behavior confirmed by multiple sources; sandbox mechanics confirmed against Apple developer forums)

---

## Critical Pitfalls

### Pitfall 1: QLPreviewPanel Conflict with NSTextView Focus

**What goes wrong:**
`QLPreviewPanel` traverses the responder chain to find the first object willing to control it. `NSTextView` has a private method `quickLookPreviewableItemsInRanges:` that intercepts that chain while the text view is focused. When the user presses spacebar to trigger Quick Look, the panel either shows nothing, errors with `-[QLPreviewPanel setDelegate:] called while the panel has no controller`, or shows text from the caption editor instead of the selected image file. The issue is silent — no crash, just wrong or missing preview.

**Why it happens:**
The responder chain is traversal-order based. Any focused `NSTextView` sits before your custom controller in that chain, and it claims panel control before your controller gets a chance. This is a private, undocumented behavior of `NSTextView`, making it easy to miss during development if you test without an active text editor focus.

**How to avoid:**
Before calling `QLPreviewPanel.shared().makeKeyAndOrderFront(nil)`, explicitly resign first responder on the text view. If using `NSViewRepresentable` for `NSTextView`, expose a method on the coordinator to call `window?.makeFirstResponder(nil)` before the preview opens. Using a `@FocusState` binding in SwiftUI to track and clear focus is the cleanest approach.

Implement the three required responder chain methods on your `NSWindowController` or a dedicated `NSResponder` subclass inserted into the chain:
- `acceptsPreviewPanelControl(_:)` → return `true`
- `beginPreviewPanelControl(_:)` → assign `dataSource` and `delegate`
- `endPreviewPanelControl(_:)` → nil out stored panel reference

**Warning signs:**
- Spacebar triggers Quick Look but panel shows blank content or flickers
- Console shows `-[QLPreviewPanel reloadData] called while the panel has no controller`
- Preview works fine when caption editor is not focused but fails when it is
- Preview requires two spacebar presses to show correctly

**Phase to address:** Phase implementing Quick Look (QLPreviewPanel). Must be addressed before any testing — the symptom only appears in integration context where NSTextView and QLPreviewPanel coexist.

---

### Pitfall 2: NSTextView updateNSView Resets Cursor Position While Typing

**What goes wrong:**
When wrapping `NSTextView` in `NSViewRepresentable`, SwiftUI calls `updateNSView(_:context:)` on every state change — including after every character typed. If `updateNSView` unconditionally sets `textView.string = binding.wrappedValue`, the cursor jumps to end of text after each keystroke. Characters typed mid-sentence appear in the wrong position, and for users editing long captions this is immediately noticeable and unusable.

**Why it happens:**
`NSViewRepresentable` is a value type. SwiftUI recreates the value wrapper frequently and calls `updateNSView` as a consequence. The naive implementation calls `nsView.string = text` every time, which replaces the entire text storage and loses selection state. The delegate's `textDidChange` fires, updates the SwiftUI binding, which triggers `updateNSView` again — a tight loop that manifests as cursor-teleporting.

**How to avoid:**
In `updateNSView`, guard against no-op updates:
```swift
func updateNSView(_ nsView: NSTextView, context: Context) {
    guard nsView.string != text else { return }
    // Only update if external change (not from user typing)
    if !context.coordinator.isEditing {
        nsView.string = text
    }
}
```
Track `isEditing` on the coordinator: set it `true` in `textDidBeginEditing`, `false` in `textDidEndEditing`. During editing, do not push the SwiftUI binding value back into the view.

**Warning signs:**
- Cursor jumps to end of text after each keystroke
- Characters typed in the middle of text appear at the wrong position
- Typing feels "laggy" or doubled
- Console shows repeated `updateNSView` calls during a single keystroke

**Phase to address:** Phase implementing NSTextView replacement for caption editor. Critical — the entire NSTextView feature is unusable without this guard.

---

### Pitfall 3: QLPreviewPanel in a Pure SwiftUI Window Has No Natural Responder Anchor

**What goes wrong:**
SwiftUI's `WindowGroup` does not expose an `NSWindowController`. `QLPreviewPanel` control methods (`acceptsPreviewPanelControl`, `beginPreviewPanelControl`, `endPreviewPanelControl`) are NSResponder methods — they require an object in the responder chain. SwiftUI views are not NSResponders. This means implementing the three control methods requires inserting a custom `NSResponder` into the chain via an `NSViewRepresentable` shim, or subclassing `NSWindow`/`NSWindowController` via `AppDelegate`. Neither is obvious and both require AppKit interop.

**Why it happens:**
SwiftUI apps use a `NSHostingView` at the root, which is an `NSView` subclass. The responder chain does go through it, but SwiftUI view bodies have no direct equivalent to `override func acceptsPreviewPanelControl`. Developers familiar with UIKit or pure SwiftUI expect a `.quickLookPreview()` modifier to work, but the macOS modifier only uses `QLPreviewController` (iOS path) and does not invoke `QLPreviewPanel` (macOS path).

**How to avoid:**
Use a thin `NSViewRepresentable` whose underlying `NSView` subclass overrides the three responder methods and acts as the preview panel controller. Place this view in the hierarchy to guarantee it's always in the responder chain. Alternatively, add an `NSWindowDelegate` via `AppDelegate` pattern and insert a custom `NSResponder` via `window.nextResponder`.

Do not use SwiftUI's `.quickLookPreview()` modifier for this — it does not use `QLPreviewPanel` on macOS and will not respond to spacebar.

**Warning signs:**
- Spacebar does nothing in the app
- `.quickLookPreview()` modifier doesn't show QLPreviewPanel (shows a sheet/popover instead)
- Console shows panel warnings about missing controller at app launch

**Phase to address:** Phase implementing Quick Look. Architectural decision made at the start of that phase.

---

### Pitfall 4: Security-Scoped Bookmarks Are Not Inherited by Finder Sync Extensions

**What goes wrong:**
If "Finder context menu" is implemented as a `FinderSync` app extension, the extension runs in its own sandbox process. The parent app's active security-scoped bookmark and `startAccessingSecurityScopedResource()` state are not shared with the extension process. Any file path the extension receives in its context menu action handler will fail access checks — `FileManager` operations on those URLs silently fail or throw permission errors. The extension cannot read or write to the user's dataset directory even though the parent app has full access.

**Why it happens:**
Security-scoped bookmarks are per-process. A `FinderSync` extension is a separate process with its own sandbox container. `startAccessingSecurityScopedResource()` on a URL in process A does not grant access to process B, even if B is the parent app's extension. This is fundamental macOS sandbox architecture and is documented in Apple Developer Forums but not prominently in guides.

**How to avoid:**
**Clarify "Finder context menu" scope before writing a line of code.** There are two distinct features with the same colloquial name:

1. **In-app context menu (SwiftUI `.contextMenu`):** Right-click on sidebar/file list rows within the app. This is pure SwiftUI, has no sandbox implication beyond what the app already has, and is the correct interpretation for this project.

2. **System Finder context menu (FinderSync extension):** A separate process that appears when right-clicking files in Finder.app itself. This requires a separate app extension target, NSXPC communication, and cannot reuse the parent app's security-scoped access.

For this project (v1.4), implement in-app context menus (option 1). Do not create a FinderSync extension. The project context confirms the goal is right-click on files and folders within the app's own sidebar — not Finder.app itself.

**Warning signs:**
- Planning docs mention "Finder-native context menu" — clarify immediately whether this means in-app or in Finder.app
- Any requirement to create a new app extension target for context menus is a signal the scope has drifted to FinderSync
- File operations in context menu action handlers fail silently

**Phase to address:** Scope clarification before the Finder context menu phase begins. This is a planning pitfall, not a code pitfall.

---

### Pitfall 5: NSTextView Undo Manager Conflicts with SwiftUI's State

**What goes wrong:**
`NSTextView` with `allowsUndo = true` manages its own undo stack internally. When a user types and then presses Cmd+Z, `NSTextView` correctly undoes the last typed character. However, if `updateNSView` is called between undo steps (e.g., SwiftUI redraws due to any other state change), the binding is updated with the post-undo text, which then gets pushed back into the view, breaking the undo chain. The user sees undo "work" once then stop, or undo silently replaces all text with the pre-edit state.

Additionally, `NSTextView`'s undo manager is the *window's* undo manager by default. If multiple `NSTextView` instances are in the view hierarchy, or if SwiftUI's TextEditor and the custom NSTextView both exist during transition, two undo managers compete.

**Why it happens:**
SwiftUI has no native concept of undo for `@State`/`@Published` values. `NSTextView.allowsUndo` works entirely at the AppKit layer. The binding is a unidirectional snapshot — it doesn't know about "undo history," so every state sync wipes undo context. This is especially dangerous during the transition from `TextEditor` to `NSTextView` if both are in the hierarchy simultaneously.

**How to avoid:**
- Never call `nsView.string = text` while `isEditing` is true (same guard as Pitfall 2)
- Remove the existing `TextEditor` from `ContentView` before adding `NSTextView` — do not have both in the view hierarchy at once
- Set `allowsUndo = true` on the `NSTextView` and let it own undo entirely; do not implement manual undo in the ViewModel for text edits
- Avoid wrapping caption text mutations (other than Save) in `undoManager.registerUndo`

**Warning signs:**
- Cmd+Z partially works (first undo works, subsequent ones don't)
- Cmd+Z replaces all text with a previous bulk state instead of character-by-character undo
- Undo/Redo menu items remain grayed out despite typing

**Phase to address:** Phase replacing `TextEditor` with `NSTextView`. Must be handled at initial implementation — retrofitting undo handling after the fact requires architectural rework.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Keep `TextEditor` alongside `NSTextView` during transition | Easier rollback | Competing undo managers, duplicate state, confusing dirty-tracking | Never — swap in one commit |
| Use `textView.string = text` unconditionally in `updateNSView` | Simpler code | Cursor jumping, broken typing | Only if the view is read-only |
| Skip `endPreviewPanelControl` cleanup | Saves a few lines | Memory leak on the shared QLPreviewPanel; stale delegate references | Never |
| Attach `.contextMenu` to individual `ForEach` rows without `contentShape` | Works most of the time | Right-click on left padding area of row misses hit target (SwiftUI bug, macOS Sonoma) | Never — always add `contentShape(Rectangle())` |
| Implement QLPreviewPanel responder in ContentView directly | Avoids new file | Makes ContentView an NSResponder subclass, breaks SwiftUI view hierarchy semantics | Never — use a dedicated NSViewRepresentable shim |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `QLPreviewPanel` + `NSTextView` | Trigger preview while text editor is focused | Call `window?.makeFirstResponder(nil)` before `makeKeyAndOrderFront` |
| `NSTextView` in `NSViewRepresentable` | Use `nsView.string = binding` unconditionally | Guard with `nsView.string != binding` and `!coordinator.isEditing` |
| `NSTextView` undo | Leave `window.undoManager` default, mix with SwiftUI state mutations | Set `allowsUndo = true`, let NSTextView own its undo stack, never externally replace text during editing |
| SwiftUI `.contextMenu` on `List` rows | Attach to the row view directly without `contentShape` | Add `.contentShape(Rectangle())` to ensure full row hit area responds to right-click |
| `contextMenu(forSelectionType:)` on `List` | Assume closure receives currently selected items | The closure receives the items being right-clicked, which may differ from `vm.selectedID`; reconcile explicitly |
| `QLPreviewPanel` responder chain | Implement control methods on a SwiftUI `View` | Implement on an `NSView` subclass used via `NSViewRepresentable`, or on an `AppDelegate`-owned `NSWindowController` |
| Security-scoped access + context menu actions | Assume active `isAccessingSecurityScope` covers the action | For in-app menus, the existing `startSecurityScopedAccess()` is sufficient; confirm it is active before performing file ops from menu actions |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `updateNSView` called on every keystroke with full string replacement | `NSTextView` freezes for long captions (1000+ chars); cursor jumps | Guard with equality check and `isEditing` flag | Any caption over ~200 characters with active typing |
| `QLPreviewPanel` loading full-resolution image synchronously on spacebar | UI freezes 1-3 seconds on large images (4K, 8K) | Return `previewItemURL` immediately; let Quick Look handle async loading internally | Images over 4 MB |
| Calling `folderTree` rebuild inside context menu action handler | Perceptible delay when menu closes | Context menu actions should only mutate selection state; do not trigger full tree scans | Any dataset with 50+ folders |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Accepting file URLs from context menu actions without path prefix validation | A malformed URL could access files outside the bookmark-granted directory | Verify URL path starts with `securedDirectoryURL.path` before any file operation |
| Storing `QLPreviewPanel` datasource URLs beyond the panel's display lifecycle | URLs held in memory after panel close may extend security-scoped access unintentionally | Nil out the items array in `endPreviewPanelControl` |
| Opening `QLPreviewPanel` for a file URL that is not within the security-scoped bookmark | Quick Look may show an access error or show a blank panel | Confirm `URL.startAccessingSecurityScopedResource()` succeeds before invoking panel |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Context menu on file items shows destructive actions (delete, rename) without confirmation | User accidentally triggers irreversible action | For v1.4 scope (reveal in Finder, open caption), confirmation is unnecessary; defer destructive actions to a later milestone |
| Quick Look panel opens but shows the caption `.txt` file instead of the image | Confusing — user expects image preview | `previewItemAt` must return `pair.imageURL`, not `pair.captionURL` |
| NSTextView loses scroll position when it gains focus (text view scrolls to cursor) | Disorienting when editing long captions | Set `textView.scrollRangeToVisible(NSRange(location: 0, length: 0))` only on initial display; do not reset on every `updateNSView` call |
| `NSTextView` replaces `TextEditor` but spell check is not enabled by default | Missing expected feature despite NSTextView capability | Explicitly set `isContinuousSpellCheckingEnabled = true` in `makeNSView` — do not rely on user defaults or system defaults |

---

## "Looks Done But Isn't" Checklist

- [ ] **QLPreviewPanel:** Focus is cleared from NSTextView before panel opens — verify by testing with cursor active in caption editor, then pressing spacebar
- [ ] **QLPreviewPanel:** `endPreviewPanelControl` is implemented and nils the delegate/dataSource — verify no console warnings after panel closes
- [ ] **NSTextView:** Cursor does not jump when typing rapidly in the middle of a 500-character caption — verify manually
- [ ] **NSTextView:** Cmd+Z undoes one character at a time (not bulk state reset) — verify by typing 5 chars then pressing Cmd+Z five times
- [ ] **NSTextView:** `isDirty` on `ImageCaptionPair` still updates correctly after replacing `TextEditor` — verify save button enables on first keystroke
- [ ] **Context menu:** Right-clicking on the left-edge padding of a folder row in the sidebar still shows the menu — verify on macOS Sonoma+ (SwiftUI hit area bug)
- [ ] **Context menu:** Right-clicking a file selects it before the menu appears — verify `vm.selectedID` is updated when menu action runs
- [ ] **Security scope:** Context menu "Reveal in Finder" action uses `NSWorkspace.shared.activateFileViewerSelecting([url])` — this works without any additional entitlements from within a sandboxed app
- [ ] **Spell check:** `isContinuousSpellCheckingEnabled` is `true` after replacing `TextEditor` with `NSTextView` — check via Edit menu

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| QLPreviewPanel NSTextView focus conflict discovered late | LOW | Add `window?.makeFirstResponder(nil)` call before panel open; 1-line fix |
| NSTextView cursor jumping discovered after integration | MEDIUM | Retrofit `isEditing` coordinator flag; requires reviewing all `updateNSView` and delegate paths |
| NSTextView undo chain broken by competing state | HIGH | Remove and re-add NSTextView from scratch with correct guard logic; undo is deeply entwined with text storage |
| FinderSync extension built instead of in-app context menu | HIGH | Entire extension target must be abandoned; re-implement using SwiftUI `.contextMenu` modifier |
| Spell check not working because `isContinuousSpellCheckingEnabled` defaults to false | LOW | Add one property set in `makeNSView`; ship as a patch |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| QLPreviewPanel + NSTextView focus conflict | Quick Look phase | Manually test spacebar with active caption editor cursor |
| NSTextView updateNSView cursor reset | NSTextView replacement phase | Type rapidly in the middle of a long caption; cursor must not jump |
| QLPreviewPanel responder chain anchor in SwiftUI | Quick Look phase (architecture decision) | `acceptsPreviewPanelControl` must be hit on first spacebar press |
| FinderSync scope creep | Finder context menu phase (scope definition step) | No new app extension targets created |
| Security-scoped bookmark not crossing process boundary | Context menu phase | No FinderSync targets = this is not applicable |
| NSTextView undo breaking | NSTextView replacement phase | Cmd+Z must undo one character at a time |
| Context menu hit area on List rows | Context menu phase | Right-click on far-left of sidebar row must trigger menu |
| Spell check disabled by default | NSTextView replacement phase | Confirm spell-check red underlines appear on misspelled words |

---

## Sources

- [QuickLook + TextView Trouble — Michael Berk](https://mberk.com/posts/QuickLook+TextViewTrouble/) — NSTextView / QLPreviewPanel responder chain conflict (MEDIUM confidence, author confirmed the specific private method interaction)
- [DevGypsy: Quick Look with NSTableView and Swift](https://devgypsy.com/post/2023-06-06-quicklook-swift-tableview/) — `acceptsPreviewPanelControl` / `beginPreviewPanelControl` / `endPreviewPanelControl` implementation pattern (MEDIUM confidence)
- [Apple Developer Forums: NSXPCConnection between app and FinderSync extension](https://developer.apple.com/forums/thread/677665) — Security-scoped bookmarks not crossing process boundary (HIGH confidence, Apple staff confirmed)
- [Apple Developer Forums: Finder Sync Extension does not allow for sandboxed access](https://developer.apple.com/forums/thread/717098) — `startAccessingSecurityScopedResource()` does not work in FinderSync extension context (HIGH confidence)
- [Including Services in contextual menus in SwiftUI — Wade Tregaskis](https://wadetregaskis.com/including-services-in-contextual-menus-in-swiftui/) — SwiftUI contextMenu missing Services submenu; NSServicesMenuRequestor threading pitfalls (HIGH confidence, detailed original research)
- [Small click areas in SwiftUI .contextMenu with List on macOS — Cocoa Switch](https://www.cocoaswitch.com/2023/12/09/small-click-areas.html) — Left-padding hit area bug in SwiftUI List context menus (MEDIUM confidence, Sonoma-era bug, no fix confirmed)
- [Enabling Selection, Double-Click and Context Menus in SwiftUI List Rows on macOS — SerialCoder.dev](https://serialcoder.dev/text-tutorials/swiftui/enabling-selection-double-click-and-context-menus-in-swiftui-list-on-macos/) — `contextMenu(forSelectionType:)` selection behavior (HIGH confidence, official API usage)
- [Apple Developer Forums: How do I update state in NSViewRepresentable](https://developer.apple.com/forums/thread/125920) — updateNSView cursor/state pitfalls (HIGH confidence, community-confirmed)
- [MacEditorTextView gist — unnamedd](https://gist.github.com/unnamedd/6e8c3fbc806b8deb60fa65d6b9affab0) — NSTextView NSViewRepresentable reference implementation with isEditing guard (MEDIUM confidence)
- [Using NSTextView in SwiftUI — Blue Lemon bits](https://bluelemonbits.com/2021/11/14/using-nstextview-in-swiftui/) — undo manager, spell check, delegate wiring (MEDIUM confidence)

---
*Pitfalls research for: macOS native OS integration — Finder context menus, QLPreviewPanel, NSTextView in sandboxed SwiftUI + AppKit hybrid*
*Researched: 2026-03-15*

---
---

# Pitfalls Research — v1.5: Image Cache + Filesystem Watchdog

**Domain:** Image/caption LRU cache with prefetch and DispatchSource filesystem watchdog added to existing sandboxed macOS SwiftUI + AppKit app
**Researched:** 2026-03-16
**Confidence:** HIGH for DispatchSource lifecycle and security-scoped bookmark mechanics (Apple official docs + confirmed community reports); MEDIUM for @MainActor/prefetch race patterns (Swift concurrency docs + confirmed forum reports); MEDIUM for NSCache behavior on macOS (Apple docs confirm API, eviction timing is implementation-defined)

---

## Critical Pitfalls

### Pitfall 6: DispatchSource (VNODE) Requires One Open File Descriptor Per Watched File

**What goes wrong:**
`DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)` requires a live, open file descriptor for every file being watched. The descriptor must stay open for the entire lifetime of the source. If you want to watch a directory containing 500 images and their 500 caption files, you need up to 1,000 open file descriptors simultaneously. macOS defaults the soft limit to 256 file descriptors per process. At ~257 images the watcher silently stops registering new descriptors and monitoring ceases for those files without error.

**Why it happens:**
VNODE dispatch sources are kernel-level constructs tied to a vnode via an `fd`. The kernel tracks which fds have pending events. Opening with `O_EVTONLY` prevents the descriptor from blocking unmount but does not reduce count toward the per-process limit. Developers often test with small directories (10-20 files) and never encounter the wall.

**How to avoid:**
Watch the directory itself (one fd), not individual files. A single VNODE source on a directory's fd fires `.write` events when files inside are added, removed, or renamed. For content-change detection on specific files (e.g., a caption `.txt`), use `NSFilePresenter` or watch only the currently selected file's descriptor. Never open a descriptor per image in the cache. Close and cancel the source with a proper cancel handler:
```swift
source.setCancelHandler { close(fd) }
source.resume()
// in deinit: source.cancel()
```
If you must watch multiple files, keep a pool limited to `min(watchCount, 64)` and rotate based on selection.

**Warning signs:**
- Filesystem events stop firing for files after adding more than ~200 to watch list
- `open()` calls silently return `-1` with `errno == EMFILE`
- App runs fine in small test datasets but breaks on real 500+ image folders
- Instruments shows file descriptor count climbing and plateauing

**Phase to address:** Watchdog phase — architecture decision before writing the watcher class. Choose directory-level watching as the primary strategy.

---

### Pitfall 7: Security-Scoped Access Must Be Active When Opening the Watched File Descriptor

**What goes wrong:**
Opening a file descriptor for VNODE watching (`open(path, O_EVTONLY)`) requires the file to be within the sandbox's current access grants. In this app, the access grant comes from `startAccessingSecurityScopedResource()` called at directory selection. If the watchdog creates its directory `fd` before security-scoped access is started, `open()` returns `-1` (permission denied) and the source is never created. More subtly, if the watcher is initialized during session restore (which happens in `Task { await restorePreviousDirectoryIfAvailable() }`), there is a window between app launch and the async task completing where `startAccessingSecurityScopedResource()` has not been called yet.

**Why it happens:**
The app currently calls `startSecurityScopedAccess()` inside `restorePreviousDirectoryIfAvailable()` and `chooseDirectory()`. Any code that runs before these complete — including code triggered by `init()` — cannot open file descriptors to the watched directory.

**How to avoid:**
Initialize the watchdog after `startSecurityScopedAccess()` completes, not in `DatasetViewModel.init()`. The correct place is at the end of both `restorePreviousDirectoryIfAvailable()` and `chooseDirectory()`, after `isAccessingSecurityScope` is confirmed `true`. Pass the `securedDirectoryURL` to the watchdog, not the raw `directoryURL`. When tearing down (new directory selected or app quits), call `source.cancel()` before `stopAccessingSecurityScopedResource()` — never the reverse order.

**Warning signs:**
- `open()` returns -1 at watchdog initialization but works if you re-select the folder
- Watchdog starts correctly on first launch after folder picker, fails on session restore
- No FS events fired until the user manually navigates to a subfolder

**Phase to address:** Watchdog phase — initialization sequencing is the first design decision.

---

### Pitfall 8: DispatchSource VNODE on a Directory Fires on Its Own Write Events

**What goes wrong:**
When the app saves a caption file (writes to the watched directory), the VNODE source on the directory fires a `.write` event. The event handler then scans the directory and may reload the caption that was just saved, producing a reload loop: save → event → reload caption → dirty state cleared unexpectedly → user's in-progress edits lost.

**Why it happens:**
VNODE dispatch sources on directories detect any modification to the directory's metadata (file additions, removals, renames). A `write(to:atomically:)` call creates a temp file and renames it into place, producing two events: a `.rename` (temp file created) and a `.write` (rename into final position). Both fire on the directory watcher.

**How to avoid:**
In the event handler, before reloading, compare the file's modification date (`URLResourceValues.contentModificationDate`) against a timestamp recorded at save time. If the modification date is within a 2-second window of the last save by this app, suppress the reload. Alternatively, track the last-saved URL: if the event is for the file the app just wrote, skip the external-change path.

For caption files specifically, only trigger a reload if the modification date is newer than `savedCaptionText`'s last-sync time AND the caption is not currently dirty (`editingIsDirty == false`). Never overwrite a dirty caption with an external change silently.

**Warning signs:**
- Caption text disappears or reverts immediately after Cmd+S
- `captionReloadToken` increments twice per save (once from save, once from spurious event)
- Console shows reload calls within 1 second of save calls

**Phase to address:** Watchdog phase — implement the event handler with this suppression logic from the start.

---

### Pitfall 9: Prefetch Task Delivers a Stale Image After Selection Changes

**What goes wrong:**
`ContentView.loadImageForSelection()` uses `Task.detached` to load an `NSImage` off the main thread, then calls `await MainActor.run` to assign it. If the user navigates quickly (arrow keys), multiple detached tasks are in-flight simultaneously. The last task to complete wins, potentially assigning the image for item N-2 while item N is now selected. The wrong image is displayed with no visual error.

**Why it happens:**
The current code already has a `guard self.selectedFileID == id else { return }` check. However the cache prefetch (neighbors N-1 and N+1) loads images independently. If prefetch for item N+1 completes before prefetch for item N, and the user then navigates to N+1, the prefetch task's final `await MainActor.run` still checks an `id` captured at task creation — but that captured `id` is now the same as the current selection. The guard passes, and the image (which happens to be the right one) is set, but the race itself is real and will misfired under slightly different timing.

The deeper issue: `Task.detached` does not cancel when the parent scope changes. If `loadImageForSelection()` is called for item A, and then immediately called for item B, the task for item A continues running and its completion check only catches the race if selection has already changed — not if it changes after the check.

**How to avoid:**
Store the active load task and cancel it explicitly before starting a new one:
```swift
private var loadTask: Task<Void, Never>?

private func loadImageForSelection() {
    loadTask?.cancel()
    let id = selectedFileID
    loadTask = Task.detached {
        let image = NSImage(contentsOf: url)
        await MainActor.run {
            guard !Task.isCancelled, self.selectedFileID == id else { return }
            self.loadedImage = image
        }
    }
}
```
Check `Task.isCancelled` before the `await MainActor.run` call for early exit on long-running loads. For prefetch, use a separate `[UUID: Task<NSImage?, Never>]` dictionary and cancel tasks for items that leave the prefetch window.

**Warning signs:**
- Rapidly pressing arrow keys occasionally shows wrong image before correcting itself
- Image for item N flickers to item N-1 and back
- Under Instruments Time Profiler, image decode work continues after navigation for 200-500ms

**Phase to address:** Cache/prefetch phase — task cancellation pattern must be designed into the prefetch manager, not retrofitted.

---

### Pitfall 10: Dirty Caption Conflict When External Change Arrives

**What goes wrong:**
The user is editing caption for image A (dirty state: `editingIsDirty == true`). An external tool (e.g., a training script) rewrites `A.txt` on disk. The filesystem watcher fires, the event handler reloads `A.txt`, calls `reloadCaptionForSelected()`, which overwrites `pairs[idx].captionText` and increments `captionReloadToken`. `CaptionEditingContainer` observes the token change, calls `syncFromVM()`, and replaces `localText` with the disk version. The user's unsaved edits are silently discarded.

**Why it happens:**
The current `reloadCaptionForSelected()` unconditionally replaces `captionText` and `savedCaptionText`, then signals the editor to re-sync. There is no dirty-state guard. External reloads triggered by the watchdog follow the same code path as the user pressing Cmd+Shift+R ("Reload Caption"), which is intentionally destructive.

**How to avoid:**
In the watchdog's event handler for caption files, check `editingIsDirty` before reloading. If dirty:
- Update `savedCaptionText` only (disk version) but do not touch `captionText` or signal the editor
- Set a `@Published var externalCaptionPending: Bool` flag on the ViewModel
- Show a non-blocking banner: "Caption changed externally. Reload?" with Reload / Keep Mine buttons
If not dirty, reload silently and transparently.

For image files (not captions), always reload without prompting — there is no user-editable image state to conflict with.

**Warning signs:**
- User edits disappear without warning after an external tool runs
- `captionReloadToken` increments while `editingIsDirty == true`
- "Unsaved changes" indicator (orange dot) disappears unexpectedly

**Phase to address:** Watchdog phase — implement dirty-state guard in the event handler before integration testing. A separate `externalCaptionPending` state may warrant its own UI phase.

---

### Pitfall 11: NSCache totalCostLimit Set in Bytes But Populated with NSImage, Whose Memory Cost is Not Its File Size

**What goes wrong:**
The developer sets `cache.totalCostLimit = 200 * 1024 * 1024` (200 MB) and inserts each `NSImage` with `cost: fileSize` obtained from `URLResourceValues.fileSize`. The cache appears to stay within limit. In reality, `NSImage` in memory is fully decoded: a 2 MB JPEG expands to `width × height × 4 bytes` (RGBA) in the image representation. A 4000×3000 PNG is 48 MB decoded, not the 3 MB file size. The cache holds 5-10 images before actual memory usage far exceeds the limit, while `NSCache` believes only 10-15 MB is used. Memory pressure builds silently and the app is jettisoned.

**Why it happens:**
`totalCostLimit` is advisory and the cost value is whatever the caller supplies. `NSCache` has no intrinsic understanding of `NSImage` memory footprint. The natural instinct is to use file size as cost. File size and decoded memory footprint diverge drastically for compressed formats.

**How to avoid:**
Calculate the actual decoded byte cost before inserting:
```swift
let byteCost = Int(image.size.width * image.size.height) * 4 // RGBA, 8-bit
cache.setObject(image, forKey: url as NSURL, cost: byteCost)
```
For `NSImage` backed by multiple representations, use the largest representation's pixel dimensions. As a conservative upper bound, `image.size.width * image.size.height * 4` (points, not pixels — scale factor applies on Retina but NSImage.size is in points) gives a reasonable approximation without inspecting each representation. For LoRA datasets, images are commonly 512×512 to 2048×2048 at 1× (already in pixels), so `size` matches pixel count.

Set `totalCostLimit` to a fraction of available physical RAM, not a fixed byte constant:
```swift
let totalRAM = ProcessInfo.processInfo.physicalMemory
cache.totalCostLimit = Int(Double(totalRAM) * 0.15) // 15% of RAM
```

**Warning signs:**
- App memory usage in Activity Monitor grows past 500 MB with 20+ images cached
- Memory pressure warnings (yellow/red) appear in Xcode's memory gauge
- App gets jettisoned on systems with 8 GB RAM after viewing ~30 images
- `cache.totalCostLimit` is set but `cache.totalCost` (not public API — only visible via Instruments) shows far less than actual memory

**Phase to address:** Cache phase — cost calculation must be correct at initial implementation.

---

### Pitfall 12: Accessing @MainActor-Isolated ViewModel State from the Watchdog's Background Queue

**What goes wrong:**
The DispatchSource event handler fires on a background dispatch queue (the queue passed to `makeFileSystemObjectSource`). If the handler directly accesses `vm.pairs`, `vm.selectedID`, or `vm.editingIsDirty`, it reads `@MainActor`-isolated state from an off-actor context. In Swift 5.9+ with strict concurrency checking, this is a compile-time error. In Swift 5.7-5.8 with default checking, it compiles but causes data races: the background queue reads `pairs` while the main actor is mutating it.

**Why it happens:**
`DispatchSource` is a GCD construct predating Swift Concurrency. Its event handler closure has no actor context. The developer wires it up in a `class WatchdogMonitor` that holds a `weak var vm: DatasetViewModel?` and naively accesses `vm?.editingIsDirty` in the handler. This looks correct (it's a read-only access) but violates `@MainActor` isolation.

**How to avoid:**
The event handler must dispatch back to the main actor for any ViewModel interaction. Use `Task { @MainActor in ... }` inside the handler:
```swift
source.setEventHandler {
    Task { @MainActor in
        guard let vm = self.vm else { return }
        // safe to read/write vm here
        vm.handleFilesystemEvent(url: watchedURL)
    }
}
```
Move all ViewModel-touching logic into a method on `DatasetViewModel` annotated `@MainActor`. The watchdog only calls into the ViewModel via this dispatch; it never reads ViewModel state directly.

Do not use `DispatchQueue.main.async` — use `Task { @MainActor in }` to stay in the Swift Concurrency model and enable proper cancellation.

**Warning signs:**
- Swift 6 or strict concurrency warnings: "Sending 'self' risks causing data races"
- Thread Sanitizer (TSan) reports data races on `pairs` or `selectedID` under rapid navigation
- App crashes with `EXC_BAD_ACCESS` when navigating while the watchdog is active

**Phase to address:** Watchdog phase — actor boundary design is the foundational decision before any ViewModel access from the watcher.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Use file size as NSCache cost instead of decoded byte size | Simple to implement | Silent memory bloat; app jettisoned under memory pressure | Never — decoded size is one multiply away |
| Watch each file individually with a VNODE source | Fine-grained change detection | File descriptor exhaustion at 257+ files; watcher silently stops | Never for a directory-wide watcher; acceptable for the single selected file only |
| Allow watchdog to reload caption when `editingIsDirty == true` | No special-case code needed | User loses unsaved edits silently | Never — this is data loss |
| Omit `Task.isCancelled` check in prefetch tasks | Simpler task body | Stale image appears when navigating quickly | Never — the guard is one line |
| Set `cache.totalCostLimit` to a fixed MB constant | Predictable | OOM on 8 GB machines, underutilizes 64 GB machines | Acceptable only as a conservative floor: `max(fixedLimit, 0.10 * RAM)` |
| Cancel the DispatchSource in `deinit` without a cancel handler to close the fd | Avoids cancel handler boilerplate | File descriptor leaked until process exits | Never — always pair cancel handler with `close(fd)` |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| DispatchSource + security-scoped bookmarks | Open watched fd before `startAccessingSecurityScopedResource()` | Initialize watchdog at the end of `startSecurityScopedAccess()`, after access confirmed |
| DispatchSource + app's own write | Treat every VNODE event as external change | Suppress events within 2 seconds of app's own save; compare mod date to last-save timestamp |
| NSCache + NSImage | Use file size as cost | Use decoded pixel area × 4 bytes as cost |
| Prefetch tasks + `@MainActor` ViewModel | `Task.detached { await MainActor.run { vm.loadedImage = ... } }` without cancel check | Store task reference, cancel on new selection, check `Task.isCancelled` before MainActor dispatch |
| DispatchSource event handler + `@MainActor` ViewModel | Access `vm.pairs` directly in the GCD handler closure | Dispatch all ViewModel access via `Task { @MainActor in vm.method() }` |
| NSCache eviction + `NSViewRepresentable` image view | Cache evicts the NSImage that ZoomablePannableImage is currently displaying | Cache must not evict the currently displayed image; keep a strong reference in `ContentView.loadedImage` in addition to the cache entry |
| Watchdog teardown + directory change | Cancel watchdog before starting new one; old watcher fires events for the old directory | `stopWatching()` as first action in `navigateToFolder()` and `chooseDirectory()`, before updating `directoryURL` |
| macOS 15.0 / Sequoia security-scoped bookmarks bug | Assume bookmarks always resolve correctly | Handle `isStale == true` gracefully; prompt user to re-select folder; note fixed in macOS 15.1 |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Prefetch 10+ images ahead with full-resolution decode | Memory spikes to 2+ GB; scroll stutter | Prefetch N±2 neighbors only; decode at display resolution | Any folder with images >2 MP |
| Re-scan entire directory on every VNODE event | Perceptible lag (100-300 ms) on each file change | Diff against existing `pairs` array; only add/remove changed entries | Directories with >50 files |
| Dispatch VNODE event handler on `DispatchQueue.main` | Main thread stalls during file I/O from event | Use a dedicated background queue for the source; dispatch to MainActor only for ViewModel updates | Any handler that does file stat or directory scan |
| Store `NSImage` in `NSCache` without size limit; rely solely on system pressure eviction | Memory grows unbounded for large datasets; only releases under extreme pressure | Set both `countLimit` (e.g., 30) and `totalCostLimit` (15% of RAM) as dual governors | Datasets with >20 images open simultaneously |
| Rebuild `folderTree` on every VNODE directory event | Full tree rebuild is O(depth × files); UI hitches for deep hierarchies | Watchdog events should only invalidate `pairs` for the current directory; tree rebuild only on explicit navigation or new root selection | Folder trees with >5 levels and >100 subdirs |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Passing raw `directoryURL` (not `securedDirectoryURL`) to `open()` for watchdog fd | `open()` fails or opens wrong path if URL standardization differs | Always use `securedDirectoryURL.path` for any fd-opening operation |
| Leaking `startAccessingSecurityScopedResource()` calls by cancelling DispatchSource after `stopAccessingSecurityScopedResource()` | After stop, file fd is invalid; future `open()` calls for the same scope fail until app restart | Always cancel DispatchSource (and close its fd via cancel handler) before calling `stopAccessingSecurityScopedResource()` |
| Failing to balance `startAccessingSecurityScopedResource()` calls when watchdog reinitializes | Unbalanced calls leak kernel resources; app loses sandboxed file access until relaunch | Track call count; use a single long-lived access session (as the app currently does) rather than per-operation access around the watchdog |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent caption overwrite when external change arrives during editing | User loses work with no warning | Show non-blocking conflict banner: "Caption changed on disk — Reload or Keep Mine" |
| Prefetch makes navigation feel instant for 2 images then slow for the 3rd (cold cache) | Inconsistent feel; worse than no prefetch | Warm cache on directory load (first 10 images in background); extend prefetch window to N±3 after initial warm |
| Image briefly shows previous image during fast navigation (stale task delivery) | Flickers; feels buggy | Cancel previous load task immediately; show a loading spinner if image not in cache within 100 ms |
| "Live" caption reload replaces editor content without warning while user is reading (not editing) | Startling; disrupts reading | Reload silently if the editor has never been touched (`!editingIsDirty && localText == savedText`); banner only if the user has typed |

---

## "Looks Done But Isn't" Checklist

- [ ] **DispatchSource:** Cancel handler closes the file descriptor — verify with Instruments "Open Files" instrument (fd count must drop when watchdog is stopped)
- [ ] **DispatchSource:** VNODE source initialized after `startSecurityScopedAccess()` — verify by killing and relaunching app (session restore path), confirming events fire without re-selecting folder
- [ ] **NSCache:** Cost set to decoded byte size, not file size — verify by opening a 3000×2000 image; Xcode memory gauge should increase by ~24 MB (3000×2000×4), not by the file size
- [ ] **NSCache:** `totalCostLimit` uses fraction of physical RAM, not a hardcoded constant — verify on both 8 GB and 16 GB machines (or via `ProcessInfo.processInfo.physicalMemory`)
- [ ] **Prefetch:** Previous load task cancelled on navigation — verify with Instruments "Swift Tasks" instrument; no orphaned image decode tasks after 5 rapid arrow-key presses
- [ ] **Dirty conflict:** Watchdog does NOT overwrite dirty caption — verify by editing caption, then externally modifying the .txt file; editor text must not change
- [ ] **Own-write suppression:** Cmd+S does NOT trigger a reload — verify `captionReloadToken` does not increment a second time within 2 seconds of save
- [ ] **Thread safety:** No Swift Concurrency warnings with strict checking enabled — verify by setting `SWIFT_STRICT_CONCURRENCY = complete` in build settings
- [ ] **Watchdog teardown:** Old watcher stops when navigating to new folder — verify no events from previous directory fire after switching

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| File descriptor exhaustion discovered in production with large datasets | MEDIUM | Switch watcher from per-file to directory-level; one code path change in watchdog class |
| Silent caption overwrite discovered after user data loss | HIGH | Add dirty-state guard to event handler; requires new `externalCaptionPending` state and UI banner |
| Memory bloat from wrong NSCache cost discovered via OOM reports | MEDIUM | Fix cost calculation in one line; existing cached items will use old cost until evicted |
| Stale image delivery discovered from user reports of flickering | LOW | Add `loadTask?.cancel()` + `Task.isCancelled` guard; targeted 3-line change |
| DispatchSource fd leak discovered via Instruments | LOW | Add cancel handler with `close(fd)`; requires reviewing all DispatchSource creation sites |
| @MainActor data race discovered after enabling Swift 6 | HIGH | Requires redesigning the watchdog's ViewModel interaction boundary; may need to extract a non-actor-isolated interface layer |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| VNODE fd per file → exhaustion | Watchdog architecture phase | Design review: single directory fd confirmed before implementation |
| Security-scoped access before fd open | Watchdog initialization phase | Test: session restore path fires events without re-selecting folder |
| Own-write triggers spurious reload | Watchdog event handler phase | Test: Cmd+S does not cause double-reload within 2 seconds |
| Stale prefetch image delivery | Cache/prefetch phase | Test: 10 rapid arrow key presses; no wrong image displayed |
| Dirty caption overwritten by watchdog | Watchdog + dirty state integration phase | Test: edit caption, external file write, verify editor unchanged |
| NSCache cost uses file size not decoded size | Cache phase (initial implementation) | Verify: memory delta per image matches decoded size, not file size |
| @MainActor access from GCD handler | Watchdog phase (design) | Swift strict concurrency warnings: zero warnings |
| NSCache evicts currently displayed image | Cache + image display integration | Test: view 40+ images; no crash or blank display from null cache hit |
| Watchdog teardown on folder change | Navigation + watchdog integration | Test: navigate 10 folders; no events from prior folders fire |

---

## Sources

- [DISPATCH_SOURCE_TYPE_VNODE — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatch_source_type_vnode) — VNODE event types and file descriptor requirements (HIGH confidence, official)
- [DispatchSourceFileSystemObject — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatchsourcefilesystemobject) — Swift API for file system dispatch sources (HIGH confidence, official)
- [Kernel Queues: An Alternative to File System Events — Apple Archive](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/KernelQueues/KernelQueues.html) — Per-file fd requirement, scalability warning for large hierarchies (HIGH confidence, official)
- [Dispatch Sources — Apple Concurrency Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ConcurrencyProgrammingGuide/GCDWorkQueues/GCDWorkQueues.html) — Cancel handler must close fd; source lifecycle requirements (HIGH confidence, official)
- [DispatchSource: Detecting changes in files and folders in Swift — SwiftRocks](https://swiftrocks.com/dispatchsource-detecting-changes-in-files-and-folders-in-swift) — Practical patterns; editor rename/replace event behavior (MEDIUM confidence, community)
- [Monitoring Files Using Dispatch Sources — agostini.tech](https://agostini.tech/2017/08/06/monitoring-files-using-dispatch-sources/) — O_EVTONLY usage, cancel handler in deinit pattern (MEDIUM confidence, community)
- [NSCache — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/nscache) — totalCostLimit advisory, thread-safety, auto-eviction on memory pressure (HIGH confidence, official)
- [Caching and Purgeable Memory — Apple Performance Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/CachingandPurgeableMemory.html) — Cost-based eviction semantics (HIGH confidence, official)
- [Accessing files from the macOS App Sandbox — Apple Developer Documentation](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox) — Kernel resource leak from unbalanced start/stop calls (HIGH confidence, official)
- [stopAccessingSecurityScopedResource — Apple Developer Forums](https://developer.apple.com/forums/thread/84951) — Unbalanced calls lose sandbox file access until relaunch (HIGH confidence, Apple engineer confirmed)
- [Sequoia Security Scoped Bookmarks Bug — Michael Tsai](https://mjtsai.com/blog/2024/10/10/sequoia-security-scoped-bookmarks-bug/) — macOS 15.0/15.0.1 ScopedBookmarksAgent bug; fixed in 15.1 beta 4 (HIGH confidence, confirmed by Apple DTS)
- [Task with @MainActor gotcha in Swift — Augmented Code](https://augmentedcode.io/2024/05/20/task-with-mainactor-gotcha-in-swift/) — Closure isolation must be explicit; Task inherits actor but closure parameter does not (MEDIUM confidence, confirmed pattern)
- [Task Cancellation in Swift Concurrency — Swift with Majid](https://swiftwithmajid.com/2025/02/11/task-cancellation-in-swift-concurrency/) — Swift tasks are cooperative; isCancelled must be checked explicitly (HIGH confidence, current Swift docs)
- [NSFilePresenter — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/nsfilepresenter) — `presentedItemDidChange()` for file coordination; alternative to raw DispatchSource for sandboxed access (HIGH confidence, official)
- [The Role of File Coordinators and Presenters — Apple File System Guide](https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileCoordinators/FileCoordinators.html) — Dispatch change handling asynchronously from presenter method (HIGH confidence, official)
- [LRUCache — nicklockwood/LRUCache (GitHub)](https://github.com/nicklockwood/LRUCache) — Open-source LRU with predictable eviction order; NSCache eviction order is undocumented (MEDIUM confidence, community)

---
*Pitfalls research for: image/caption LRU cache with prefetch and DispatchSource filesystem watchdog in sandboxed macOS SwiftUI + AppKit app*
*Researched: 2026-03-16*
