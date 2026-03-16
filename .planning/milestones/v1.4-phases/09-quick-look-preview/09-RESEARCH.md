# Phase 9: Quick Look Preview - Research

**Researched:** 2026-03-16
**Domain:** macOS QLPreviewPanel (QuickLookUI), SwiftUI key press handling, NSResponder chain
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Spacebar key capture:** Use SwiftUI `.onKeyPress` (macOS 14+) — bumping minimum deployment target to macOS 14 is acceptable
- **Spacebar scope:** Active in sidebar and image pane, but NOT in caption editor (where it types a space)
- **Universal dismiss:** When QL panel is visible, spacebar dismisses it regardless of focus (universal toggle)
- **Escape dismiss:** Escape also dismisses the QL panel (per QLPV-02)
- **No-op case:** Spacebar does nothing when no image file is selected (folder selected or no selection)
- **Panel follows selection:** QL panel auto-updates to show newly selected image when selection changes (matches Finder behavior)
- **Arrow key navigation:** Arrow key navigation in sidebar updates the QL panel automatically
- **Folder navigation closes panel:** Panel closes when user navigates to a different folder (selection clears = panel closes)
- **Panel architecture:** Manual `QLPreviewPanel.shared()` via AppKit — no SwiftUI `.quickLookPreview` modifier (avoids sheet-vs-floating-panel risk)
- **Refactor:** Build proper `QLPreviewPanelDelegate` + `QLPreviewPanelDataSource` pattern, replacing Phase 8's minimal `QLPreviewHelper`
- **Delete `QLPreviewHelper.swift`:** Build new QL infrastructure as a dedicated controller or directly on ViewModel
- **Unified entry point:** Context menu "Quick Look" and spacebar use the same code path

### Claude's Discretion
- Whether QL delegate/data source lives on ViewModel or a separate controller class
- How to detect caption editor focus for spacebar suppression
- NSResponder chain setup for proper QLPreviewPanel delegate forwarding
- Animation/transition behavior when panel updates to a new image

### Deferred Ideas (OUT OF SCOPE)
- Batch Quick Look cycling through multiple selected images (QLPV-04 in future requirements)
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| QLPV-01 | User can press spacebar to open Quick Look preview of selected image | `.onKeyPress` on sidebar/image pane views + `QLPreviewPanel.shared().makeKeyAndOrderFront(nil)` |
| QLPV-02 | User can press spacebar again or Escape to dismiss the preview | Toggle logic: `panel.isVisible` check; Escape via `.onKeyPress(.escape, ...)` |
| QLPV-03 | Quick Look shows the native floating QLPreviewPanel (not a sheet) | Manual `QLPreviewPanel.shared()` via AppKit — confirmed floating panel, not sheet |
</phase_requirements>

---

## Summary

Phase 9 wires the native macOS `QLPreviewPanel` (from the `QuickLookUI` framework) to the spacebar key and makes it follow selection changes. The existing `quickLook(url:)` method in `DatasetViewModel` already demonstrates the core panel toggle pattern; this phase promotes it to a proper `QLPreviewPanelDataSource` + `QLPreviewPanelDelegate` implementation using the NSResponder chain, then connects it to the spacebar via SwiftUI `.onKeyPress`.

The critical design challenge is the three-way interaction between: (1) the NSResponder chain that `QLPreviewPanel` uses to find its controller, (2) SwiftUI's `.onKeyPress` which fires only when the receiving view has focus, and (3) the `NSTextView`-based caption editor which hijacks both the responder chain and key events. The established project workaround — `NSApp.keyWindow?.makeFirstResponder(nil)` before showing the panel — addresses the NSTextView hijack and is confirmed working from Phase 8.

The SwiftUI `.quickLookPreview` modifier was explicitly ruled out (per CONTEXT.md) because it risks producing a sheet instead of a floating panel. Manual `QLPreviewPanel.shared()` is the correct approach and matches Finder behavior precisely.

**Primary recommendation:** Implement `QLPreviewPanelDataSource` + `QLPreviewPanelDelegate` conformance on `DatasetViewModel` (already the central state holder), add `acceptsPreviewPanelControl` / `beginPreviewPanelControl` / `endPreviewPanelControl` overrides on an `NSWindowController` subclass or `AppDelegate` to anchor the responder chain, and attach `.onKeyPress(.space, ...)` on the sidebar `List` and image pane.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| QuickLookUI | macOS 10.6+ | `QLPreviewPanel`, `QLPreviewPanelDataSource`, `QLPreviewPanelDelegate`, `QLPreviewItem` | Apple's only API for the native floating QL panel on macOS |
| AppKit | macOS 14+ | NSResponder chain, NSWindowController, key events | Required for panel responder chain integration |
| SwiftUI | macOS 14+ | `.onKeyPress` modifier | Locked decision; handles spacebar in sidebar and image pane |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Quartz (import) | macOS 10.6+ | Import alias that includes QuickLookUI | `import Quartz` already in project; provides QL types |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual `QLPreviewPanel.shared()` | `.quickLookPreview` SwiftUI modifier | Modifier risks showing a sheet, not floating panel; ruled out by user decision |
| NSWindowController responder chain anchor | NSViewController anchor | NSWindowController is higher in responder chain; more reliable for app-level panel control |

**Installation:** No new packages required. `import Quartz` (already present) provides all QL types.

---

## Architecture Patterns

### Recommended Project Structure

The new QL infrastructure replaces `QLPreviewHelper.swift`. Two options exist (Claude's discretion):

**Option A — DatasetViewModel as controller (simpler, fewer files):**
```
lora-dataset/
├── DatasetViewModel.swift        # Add QLPreviewPanelDataSource + QLPreviewPanelDelegate conformance
├── lora_datasetApp.swift         # NSWindowController subclass with acceptsPreviewPanelControl overrides
├── ContentView.swift             # Add .onKeyPress(.space) to List and image pane
└── [DELETE] QLPreviewHelper.swift
```

**Option B — Dedicated QLController class (cleaner separation):**
```
lora-dataset/
├── QLPreviewController.swift     # New: NSObject conforming to DataSource + Delegate
├── DatasetViewModel.swift        # Holds reference to QLPreviewController; calls toggle
├── lora_datasetApp.swift         # NSWindowController subclass with responder chain overrides
├── ContentView.swift             # Add .onKeyPress(.space) to List and image pane
└── [DELETE] QLPreviewHelper.swift
```

**Recommendation:** Option A — `DatasetViewModel` already holds `selectedPair` (the URL needed) and is `@MainActor`. Fewer objects to coordinate.

### Pattern 1: NSResponder Chain Anchor for QLPreviewPanel

**What:** `QLPreviewPanel.shared()` searches the responder chain for the first object returning `true` from `acceptsPreviewPanelControl`. On macOS with SwiftUI's `WindowGroup`, the app has no `NSWindowController` subclass by default — so you must inject one.

**When to use:** Required whenever a macOS app needs proper QLPreviewPanel integration (not just the minimal Phase 8 approach of directly setting `panel.dataSource`).

**How to inject NSWindowController in SwiftUI app:**

```swift
// Source: Apple developer forums + confirmed community pattern
// In lora_datasetApp.swift or a dedicated file

class QLWindowController: NSWindowController {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // delegate/dataSource are set on the panel here
        // typically forwarded to the ViewModel
        panel.dataSource = qlDataSource
        panel.delegate = qlDelegate
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
```

To hook this into a SwiftUI `WindowGroup`, you can use `NSApplication.shared.mainWindow?.windowController` — but a more reliable approach is to use `NSWindowController` via an `NSViewRepresentable` shim or by observing `NSWindow.didBecomeKeyNotification`. See Pitfall 2 below.

**Alternative anchor — AppDelegate approach:**

```swift
// Source: established pattern from Apple developer community
class AppDelegate: NSObject, NSApplicationDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { return true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
```

Then in `lora_datasetApp`:
```swift
@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

**Recommendation:** Use `@NSApplicationDelegateAdaptor` — it is the standard SwiftUI pattern for adding `NSApplicationDelegate` to a SwiftUI lifecycle app, is already well-understood, and places the responder chain anchor at app level (highest priority).

### Pattern 2: QLPreviewPanelDataSource Methods

**What:** Two methods the panel calls to get items to show.

```swift
// Source: Apple official docs — QLPreviewPanelDataSource protocol
func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    return currentPreviewURL != nil ? 1 : 0
}

func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
    return currentPreviewURL as QLPreviewItem?
}
```

`currentPreviewURL` is the selected image's URL, driven by `vm.selectedPair?.imageURL`.

### Pattern 3: Spacebar Toggle via `.onKeyPress`

**What:** SwiftUI `.onKeyPress` (macOS 14+) intercepts spacebar on focusable views. It fires only when the view receiving the modifier has focus.

**When to use:** For sidebar `List` focus (user navigating with keyboard) and image pane (user has clicked on image).

```swift
// Source: Apple Developer Documentation — onKeyPress(_:action:)
// macOS 14+ (SwiftUI)
List(selection: $selectedFileID) { ... }
    .focusable()
    .onKeyPress(.space) {
        guard vm.selectedID != nil else { return .ignored }
        vm.toggleQuickLook()
        return .handled
    }
```

**Caption editor suppression:** `.onKeyPress` does not fire when `NSTextView` (the caption editor's backing view) has focus, because `NSTextView` consumes key events at the AppKit level before SwiftUI sees them. This is the desired behavior — spacebar in the caption editor types a space, not open QL.

**Universal dismiss when panel is visible:** Because spacebar in the caption editor does NOT fire `.onKeyPress`, the "spacebar closes panel even from caption editor" requirement from CONTEXT.md needs a different mechanism. See Pitfall 3.

### Pattern 4: Panel Selection Following

**What:** When the panel is already open and the user selects a different image, the panel should update to show the new image.

```swift
// In DatasetViewModel
var selectedID: UUID? = nil {
    didSet {
        // ... existing persistence code ...
        if QLPreviewPanel.sharedPreviewPanelExists(),
           QLPreviewPanel.shared()!.isVisible {
            QLPreviewPanel.shared()!.reloadData()
        }
    }
}
```

`reloadData()` calls back to `numberOfPreviewItems` and `previewItemAt` with the updated `selectedPair?.imageURL`.

### Pattern 5: Panel Close on Folder Navigation

**What:** `loadDirectory()` / `navigateToFolder()` clears `pairs` and resets `selectedID = nil`, which should also close the panel.

```swift
// In navigateToFolder(_:) and after loadDirectory()
if QLPreviewPanel.sharedPreviewPanelExists(),
   QLPreviewPanel.shared()!.isVisible {
    QLPreviewPanel.shared()!.orderOut(nil)
}
```

### Pattern 6: Unified Toggle Method

```swift
// In DatasetViewModel — replaces quickLook(url:) and QLPreviewHelper
func toggleQuickLook() {
    guard let url = selectedPair?.imageURL else { return }

    // Resign first responder to prevent NSTextView hijacking QL responder chain
    NSApp.keyWindow?.makeFirstResponder(nil)

    let panel = QLPreviewPanel.shared()!
    if panel.isVisible {
        panel.orderOut(nil)
    } else {
        panel.updateController()  // force responder chain re-scan
        panel.makeKeyAndOrderFront(nil)
    }
}
```

### Anti-Patterns to Avoid

- **Directly setting `panel.dataSource` without responder chain anchor:** Works for one call but breaks when panel is hidden/shown again (Phase 8's current approach). Replace with proper `beginPreviewPanelControl`.
- **Checking `QLPreviewPanel.sharedPreviewPanelExists()` before `shared()`:** The panel is lazily created on first call to `shared()`. Only use `sharedPreviewPanelExists()` when you want to avoid creating the panel (e.g., checking visibility before the panel was ever opened).
- **Calling `reloadData()` when no controller is set:** Produces console warnings. Always guard with `panel.isVisible` before calling.
- **Using `.quickLookPreview` modifier:** Produces a sheet on macOS, not a floating panel.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File preview floating panel | Custom NSPanel with WKWebView or NSImageView | `QLPreviewPanel` | System panel handles all file types, animations, fullscreen, keyboard navigation |
| Image type detection for previews | Manual UTType checking | QL handles all types automatically | QL knows about all registered file types via UTI system |
| Panel open/close animation | Custom NSWindow animation | `makeKeyAndOrderFront` / `orderOut` | System uses standard QL animation matching Finder |

**Key insight:** `QLPreviewPanel` is a singleton managed by the system. The developer only needs to tell it what to show (data source) and when to appear/disappear. The panel handles animation, keyboard cycling, fullscreen, and type rendering.

---

## Common Pitfalls

### Pitfall 1: NSTextView Hijacks QLPreviewPanel Responder Chain
**What goes wrong:** When an `NSTextView` (caption editor) has focus, `QLPreviewPanel` scans the responder chain and finds the text view's private `quickLookPreviewableItemsInRanges:` method. The panel shows empty or fails to display on first invocation.
**Why it happens:** `NSTextView` contains private QL-related methods that intercept the responder chain scan. The system sees the text view as a QL controller and uses it instead of the intended data source.
**How to avoid:** Call `NSApp.keyWindow?.makeFirstResponder(nil)` immediately before showing the panel. This is the established project pattern from Phase 8. Also, calling `panel.updateController()` after clearing first responder forces a re-scan.
**Warning signs:** Panel shows blank or grey content on first spacebar press but works on second press.

### Pitfall 2: No NSWindowController in SwiftUI Lifecycle Apps
**What goes wrong:** `acceptsPreviewPanelControl` is never called because no object in the responder chain implements it. The panel has no controller and shows no content, or shows a warning: "QLPreviewPanel: a panel requires a controller."
**Why it happens:** SwiftUI's `WindowGroup` does not create an `NSWindowController` subclass by default. The responder chain goes: NSTextView → ... → NSWindow → **NSApplication** → nil. Unless you add an anchor.
**How to avoid:** Use `@NSApplicationDelegateAdaptor` to add an `NSApplicationDelegate` subclass that overrides `acceptsPreviewPanelControl`. `NSApplicationDelegate` is in the responder chain via `NSApplication.delegate`. Alternatively, use `NSViewRepresentable` to get a reference to the `NSWindow` and install a custom `NSWindowController`.
**Warning signs:** Console warning "QLPreviewPanel: no controller found in responder chain."

### Pitfall 3: Spacebar Does Not Fire `.onKeyPress` When Caption Editor Has Focus — Universal Dismiss Conflict
**What goes wrong:** CONTEXT.md requires "spacebar closes panel even if caption editor has focus." But `.onKeyPress` does not fire when `NSTextView` is first responder (NSTextView consumes the event at AppKit level).
**Why it happens:** SwiftUI `.onKeyPress` is a SwiftUI-layer mechanism. When an `NSViewRepresentable`-wrapped `NSTextView` has focus, it becomes the AppKit first responder and eats key events before they reach SwiftUI.
**How to avoid (options):**
  - **Option A (preferred):** Override `keyDown(with:)` in the `CaptionTextView` NSTextView subclass to intercept spacebar when the QL panel is visible, then call `toggleQuickLook()`. This gives universal coverage regardless of focus.
  - **Option B:** Use `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` in `DatasetViewModel` or AppDelegate to globally intercept spacebar when the panel is visible.
  - **Option C (acceptable degradation):** Accept that spacebar only closes QL panel when caption editor is not focused. Click elsewhere first. This does not match stated Finder-like behavior.
**Recommendation:** Option A — override `keyDown` in `CaptionTextView` to check `QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared()!.isVisible` and call `toggleQuickLook()` before calling `super.keyDown`. Clean, no global monitors.
**Warning signs:** Spacebar from caption editor does nothing when QL panel is open.

### Pitfall 4: `reloadData()` Called With No Controller
**What goes wrong:** Console warning: "Update requires a controller but there is none set."
**Why it happens:** Calling `panel.reloadData()` when `panel.currentController == nil` (before `beginPreviewPanelControl` has been called, or after `endPreviewPanelControl`).
**How to avoid:** Always guard: `if panel.isVisible { panel.reloadData() }`. The panel only has a controller when it's visible (after `beginPreviewPanelControl` has been called).

### Pitfall 5: `QLPreviewItem` Conformance Requires NSObject
**What goes wrong:** `URL` conforms to `QLPreviewItem` in Swift (via a bridged extension), so returning `url as QLPreviewItem?` works — but requires the URL to not be nil. Force-unwrapping an optional URL crashes.
**How to avoid:** Guard `selectedPair?.imageURL` before returning it as `QLPreviewItem`.

---

## Code Examples

### Responder Chain Anchor via NSApplicationDelegateAdaptor

```swift
// Source: Apple Developer Documentation — @NSApplicationDelegateAdaptor + NSResponder category
// In lora_datasetApp.swift

@NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

class AppDelegate: NSObject, NSApplicationDelegate,
                   QLPreviewPanelDataSource, QLPreviewPanelDelegate {

    // Reference to ViewModel — set after ContentView initializes
    weak var viewModel: DatasetViewModel?

    // MARK: NSResponder (QLPreviewPanel)

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return true
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.delegate = self
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    // MARK: QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return viewModel?.selectedPair != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return viewModel?.selectedPair?.imageURL as QLPreviewItem?
    }
}
```

### Toggle Method in DatasetViewModel

```swift
// Source: project's existing quickLook(url:) pattern — promoted to full implementation
func toggleQuickLook() {
    guard selectedPair != nil else { return }

    // Clear first responder to prevent NSTextView hijacking QL responder chain
    NSApp.keyWindow?.makeFirstResponder(nil)

    let panel = QLPreviewPanel.shared()!
    if panel.isVisible {
        panel.orderOut(nil)
    } else {
        panel.updateController()
        panel.makeKeyAndOrderFront(nil)
    }
}
```

### Selection Following in selectedID didSet

```swift
// In DatasetViewModel.selectedID didSet
var selectedID: UUID? = nil {
    didSet {
        if let pair = selectedPair {
            UserDefaults.standard.set(pair.imageURL.path, forKey: "lastSelectedImagePath")
        }
        // Update QL panel if it's currently visible
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(),
           panel.isVisible {
            panel.reloadData()
        }
    }
}
```

### Spacebar Key Press in Sidebar List

```swift
// In ContentView.swift — on the sidebar List
List(selection: $selectedFileID) { ... }
    .onKeyPress(.space) {
        vm.toggleQuickLook()
        return .handled
    }
```

Note: `.focusable()` is not needed on `List` — it is natively focusable and `.onKeyPress` fires when the list receives focus.

### Universal Dismiss Override in CaptionTextView

```swift
// In CaptionEditorView.swift — inside CaptionTextView NSTextView subclass
override func keyDown(with event: NSEvent) {
    // Intercept spacebar to dismiss QL panel when it's visible
    if event.keyCode == 49, // 49 = spacebar
       QLPreviewPanel.sharedPreviewPanelExists(),
       let panel = QLPreviewPanel.shared(),
       panel.isVisible {
        // Find ViewModel via responder chain or notification
        // Pattern: use a static/shared reference or NotificationCenter
        panel.orderOut(nil)
        return
    }
    super.keyDown(with: event)
}
```

**Accessing ViewModel from CaptionTextView:** The cleanest approach is a `NotificationCenter` post or a weak reference injected at view creation time. Alternatively, `NSApp.sendAction(#selector(DatasetViewModel.dismissQuickLook), to: nil, from: nil)` via the responder chain (requires ViewModel to be in responder chain, which it is not by default). **Recommendation:** Use `NotificationCenter.default.post(name: .dismissQuickLook, object: nil)` — simple, decoupled.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Objective-C NSViewController QL | Swift extension on any NSObject/NSWindowController | macOS 10.6+ | Pure Swift, no bridging header needed |
| Manual `panel.dataSource = helper` (Phase 8) | Proper `acceptsPreviewPanelControl` responder chain | This phase | Panel correctly acquires controller on every show/hide cycle |
| `QLPreviewHelper` minimal class | DataSource/Delegate on AppDelegate or ViewModel | This phase | Unified, selection-aware, folder-navigation-aware |

**Deprecated/outdated:**
- `QLPreviewHelper.swift`: Delete in this phase — replaced by full DataSource/Delegate conformance
- Direct `panel.dataSource = qlPreviewHelper` without responder chain: Fragile, breaks on panel reuse

---

## Open Questions

1. **AppDelegate vs NSWindowController for responder chain anchor**
   - What we know: Both work; `@NSApplicationDelegateAdaptor` is the SwiftUI-native way to add AppDelegate
   - What's unclear: Whether `NSApplicationDelegate` is higher or lower in the responder chain than a custom `NSWindowController` installed on the window
   - Recommendation: Use `@NSApplicationDelegateAdaptor`; if QL panel does not find controller, add a `NSWindowController` subclass via `NSWindow.windowController` property override

2. **Passing ViewModel reference to AppDelegate**
   - What we know: AppDelegate is created before ContentView; ViewModel is created in ContentView via `@StateObject`
   - What's unclear: Clean way to pass `DatasetViewModel` reference to AppDelegate after initialization
   - Recommendation: Use `@EnvironmentObject` injection after window appears, OR make ViewModel initialization in AppDelegate and pass it down. Alternatively, ViewModel can hold AppDelegate reference via `NSApp.delegate as? AppDelegate`

3. **Escape key dismissal**
   - What we know: `QLPreviewPanel` may handle Escape natively when the panel has key focus (it is an NSPanel). When the QL panel is key, Escape may auto-dismiss.
   - What's unclear: Whether Escape fires when QL panel is floating but app window is key
   - Recommendation: Test empirically. If panel handles Escape natively, no code needed. If not, add `.onKeyPress(.escape, ...)` to the same views as spacebar.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`) — Xcode 16 built-in |
| Config file | None — Xcode scheme based |
| Quick run command | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset` |
| Full suite command | Same (single scheme) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| QLPV-01 | Spacebar opens QL panel for selected image | manual-only | N/A | N/A |
| QLPV-02 | Spacebar/Escape dismisses panel | manual-only | N/A | N/A |
| QLPV-03 | Panel appears as floating window, not sheet | manual-only | N/A | N/A |

**Manual-only justification:** `QLPreviewPanel` requires a running macOS window server and the shared panel singleton. It cannot be exercised in a headless `xcodebuild test` context. All three requirements are UI/behavior requirements verifiable only by running the app.

**Unit-testable aspects (supplemental, not gating):**
- `DatasetViewModel.toggleQuickLook()` guard logic (no crash when `selectedID == nil`)
- `numberOfPreviewItems` returns 0 when no selection, 1 when selection present

### Sampling Rate
- **Per task commit:** Run app, press spacebar, verify floating panel appears — manual smoke test
- **Per wave merge:** Same manual test + verify panel follows selection + verify context menu still works
- **Phase gate:** All three requirements visually verified before `/gsd:verify-work`

### Wave 0 Gaps
- None — no new test files required. Existing `lora_datasetTests.swift` can optionally receive ViewModel guard tests, but they are not required to gate this phase.

---

## Sources

### Primary (HIGH confidence)
- Apple official docs: `QLPreviewPanel` class — `/documentation/QuickLookUI/QLPreviewPanel` — panel API, responder chain behavior, `reloadData`, `updateController`
- Apple official docs: `acceptsPreviewPanelControl` — `/documentation/objectivec/nsobject-swift.class/acceptspreviewpanelcontrol(_:)` — NSObject category method
- Existing project code: `DatasetViewModel.swift:364-378` — existing `quickLook(url:)` toggle pattern (confirmed working in Phase 8)
- Existing project code: `QLPreviewHelper.swift` — existing Phase 8 minimal data source (to be deleted)

### Secondary (MEDIUM confidence)
- DevGypsy.com (2023): [Quick Look with NSTableView and Swift](https://devgypsy.com/post/2023-06-06-quicklook-swift-tableview/) — confirmed `acceptsPreviewPanelControl` / `beginPreviewPanelControl` / `endPreviewPanelControl` Swift pattern
- Michael Berk blog: [QuickLook + TextView Trouble](https://mberk.com/posts/QuickLookTrouble/) — confirmed NSTextView private method hijacks QL responder chain; `makeFirstResponder(nil)` fix

### Tertiary (LOW confidence)
- WebSearch summary: `.onKeyPress` does not fire when `NSTextView` has AppKit focus — single-source, needs empirical validation

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — `QuickLookUI` API is stable since macOS 10.6; official docs confirm all methods
- Architecture: HIGH — `acceptsPreviewPanelControl` / `beginPreviewPanelControl` / `endPreviewPanelControl` pattern is the documented Apple approach; confirmed working in community examples
- Pitfalls: HIGH (Pitfalls 1-4) / MEDIUM (Pitfall 3 spacebar+NSTextView) — Pitfall 1 is confirmed by project history and Michael Berk article; Pitfall 3 requires empirical validation
- `.onKeyPress` behavior with NSTextView: MEDIUM — consistent with SwiftUI focus model but not directly verified against this specific app

**Research date:** 2026-03-16
**Valid until:** 2026-06-16 (stable API — QLPreviewUI has not changed significantly since macOS 10.6; `.onKeyPress` added macOS 14 and stable)
