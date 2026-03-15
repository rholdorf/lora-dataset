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
