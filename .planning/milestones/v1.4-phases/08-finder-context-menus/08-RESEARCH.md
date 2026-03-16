# Phase 08: Finder Context Menus - Research

**Researched:** 2026-03-15
**Domain:** macOS SwiftUI context menus, NSWorkspace Finder integration, QLPreviewPanel
**Confidence:** HIGH

## Summary

Phase 8 adds right-click context menus to file and folder rows in the sidebar. The implementation uses SwiftUI's `.contextMenu` modifier (or the newer `contextMenu(forSelectionType:menu:primaryAction:)` on the List) attached directly to existing row views. File rows get Reveal in Finder, Open With (submenu), and Quick Look. Folder rows get Open in Finder and Open in Terminal.

The three core OS integrations — `NSWorkspace.activateFileViewerSelecting`, `NSWorkspace.open(_:withApplicationAt:)`, and `QLPreviewPanel.shared()` — are all available to sandboxed apps. The "Open in Terminal" action works via `NSWorkspace.shared.open(folderURL, withApplicationAt: terminalURL)` because `NSWorkspace.open` uses Launch Services which escapes the sandbox to launch third-party apps. `QLPreviewPanel` traverses the responder chain to find the first object that accepts control; this object must be added to the responder chain (typically via an `NSWindowController` or a `NSViewRepresentable` shim).

The critical pitfall for this phase is the interaction between `NSTextView` (currently in-focus as the caption editor) and `QLPreviewPanel`. NSTextView has a private `quickLookPreviewableItemsInRanges:` method that intercepts the Quick Look panel when the text view is focused. The fix is to resign first responder from the text view before toggling the panel. A secondary pitfall is context menu placement: since file rows use `onTapGesture` rather than a `List` with `selection:`, attaching `.contextMenu` to the row `HStack` works reliably for right-click without interfering with left-click gesture handling.

**Primary recommendation:** Attach `.contextMenu { }` directly to the row `HStack` views in ContentView (file rows) and `FolderNodeView` (folder rows). Use a helper class conforming to `QLPreviewPanelDataSource` that the window's NSWindowController (or an `NSResponder` shim) installs into the responder chain.

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**File context menu**
- Context menu targets the image file only — no caption file actions
- Same menu for all file rows regardless of caption state or selection state
- "Reveal in Finder" uses `NSWorkspace.shared.activateFileViewerSelecting([url])` to select the image file in Finder

**Folder context menu**
- "Open in Finder" opens the folder in a Finder window
- "Open in Terminal" opens Terminal.app at the folder path

**Open With submenu**
- Full app list populated via `NSWorkspace.urlsForApplications(toOpen:)` for the image file type
- Each app shows its icon (fetched via `NSWorkspace.shared.icon(forFile:)`)
- Default app shown first with bold text, remaining apps listed alphabetically
- "Other..." item at bottom separated by a divider — opens NSOpenPanel filtered to .app bundles

**Quick Look**
- Use `QLPreviewPanel.shared()` toggle with minimal data source setup
- Keep it lightweight — Phase 9 will build the full QLPreviewPanel infrastructure with spacebar support and may refactor
- Quick Look always available on any file row (not disabled for currently-selected file)
- Previews the image file only, not the caption file

### Claude's Discretion
- Menu item ordering and divider placement within the context menu
- Whether to use SwiftUI `.contextMenu` or NSMenu for implementation
- Menu item icons (SF Symbols or none)
- How to handle the QLPreviewPanel data source minimally

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CTXM-01 | User can right-click a file in sidebar to see a context menu | SwiftUI `.contextMenu` modifier on file row `HStack`; coexists with `List` selection |
| CTXM-02 | User can right-click a folder in sidebar to see a context menu | SwiftUI `.contextMenu` modifier on `FolderNodeView` outer `HStack`; must not conflict with `onTapGesture` for navigation |
| CTXM-03 | Context menu includes "Reveal in Finder" (files) / "Open in Finder" (folders) | `NSWorkspace.shared.activateFileViewerSelecting([url])` for files; `NSWorkspace.shared.open(url)` for folders |
| CTXM-04 | Context menu includes "Open With" submenu listing compatible applications | `NSWorkspace.shared.urlsForApplications(toOpen: fileURL)` to enumerate apps; icons via `NSWorkspace.shared.icon(forFile:)` |
| CTXM-05 | Context menu includes "Quick Look" to preview the file | `QLPreviewPanel.shared().toggle(self)` after ensuring a data source in responder chain; careful around NSTextView focus |
</phase_requirements>

---

## Standard Stack

### Core
| API | Version/Availability | Purpose | Why Standard |
|-----|---------------------|---------|--------------|
| SwiftUI `.contextMenu` modifier | macOS 10.15+ | Attach right-click menus to any view | Native SwiftUI, no bridging required |
| `NSWorkspace.shared.activateFileViewerSelecting(_:)` | macOS 10.0+ | Reveal file in Finder with highlight | The standard API for "Reveal in Finder" |
| `NSWorkspace.shared.open(_:)` | macOS 10.0+ | Open folder/URL in Finder | Opens folder in a Finder window |
| `NSWorkspace.shared.urlsForApplications(toOpen:)` | macOS 12.0+ (Swift) | Enumerate apps that can open a URL | Official replacement for deprecated LSCopyApplicationURLsForURL |
| `NSWorkspace.shared.icon(forFile:)` | macOS 10.0+ | Get file/app icon as NSImage | Returns 32/64/128/512px native icon |
| `NSWorkspace.shared.open(_:withApplicationAt:configuration:completionHandler:)` | macOS 10.15+ | Open file with specific application | The modern non-deprecated "Open With" API |
| `QLPreviewPanel.shared()` | macOS 10.6+ | Singleton Quick Look floating panel | Single shared instance; responder-chain driven |
| `QLPreviewPanelDataSource` | macOS 10.6+ | Protocol providing URLs to preview | Required to provide content to panel |

### Supporting
| API | Version | Purpose | When to Use |
|-----|---------|---------|-------------|
| SwiftUI `Menu` inside `.contextMenu` | macOS 11.0+ | Create nested submenus | Use for "Open With" submenu |
| `NSWorkspace.shared.urlForApplication(toOpen:)` | macOS 12.0+ (Swift) | Get default app for URL | Identify the default app to bold it |
| `NSOpenPanel` filtered to `.app` UTType | macOS 10.0+ | Browse for app bundle | "Other..." item in Open With submenu |
| `NSImage` (from `icon(forFile:)`) resized | macOS | Display app icon in menu | Set image on SwiftUI `Label` or `Button` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SwiftUI `.contextMenu` | `NSMenu` via NSViewRepresentable | NSMenu is more customizable but requires significant bridging; `.contextMenu` is simpler and fully sufficient |
| `urlsForApplications(toOpen:)` | `NSWorkspace.shared.urlsForApplications(toOpen contentType: UTType)` | Both work; URL-based version is more direct for a specific file URL |

**Installation:** No package dependencies. All APIs are part of AppKit/QuartzCore/QuickLookUI frameworks already available on macOS.

## Architecture Patterns

### Recommended Project Structure

No new files required. Attach modifiers to existing views:

```
lora-dataset/lora-dataset/
├── ContentView.swift          # Add .contextMenu to file rows + FolderNodeView
│                              # Add QLPreviewHelper to NSApp's main window responder chain
├── DatasetViewModel.swift     # Add openInTerminal(url:), revealInFinder(url:),
│                              #   openInFinder(url:), openWith(url:, appURL:) methods
└── QLPreviewHelper.swift      # NEW: NSObject conforming to QLPreviewPanelDataSource
                               #   (lightweight; Phase 9 will expand or replace)
```

### Pattern 1: File Row Context Menu

**What:** `.contextMenu` attached to the `HStack` inside `ForEach(vm.pairs)`.
**When to use:** Right-click on any file row in the "Arquivos" section.

```swift
// ContentView.swift — inside ForEach(vm.pairs)
HStack(spacing: 4) {
    Text(pair.imageURL.lastPathComponent)
    // ... existing content
}
.tag(pair.id)
.id(pair.id)
.contextMenu {
    Button {
        vm.revealInFinder(url: pair.imageURL)
    } label: {
        Label("Reveal in Finder", systemImage: "folder.badge.magnifyingglass")
    }

    Menu("Open With") {
        // populated dynamically — see Pattern 3
    }

    Divider()

    Button {
        vm.quickLook(url: pair.imageURL)
    } label: {
        Label("Quick Look", systemImage: "eye")
    }
}
```

### Pattern 2: Folder Row Context Menu

**What:** `.contextMenu` on the outer `HStack` in `FolderNodeView.body`.
**When to use:** Right-click on any folder row in the sidebar.
**Key constraint:** Must not conflict with `onTapGesture` on the folder label.

```swift
// FolderNodeView — on the outer HStack
HStack(spacing: 4) {
    // ... existing chevron + label
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
```

Note: SwiftUI `.contextMenu` (right-click) does not interfere with `onTapGesture` (left-click). They respond to different events.

### Pattern 3: Open With Submenu

**What:** Nested `Menu` inside `.contextMenu` showing all apps that can open the image file.

```swift
// Helper view or computed property
struct OpenWithMenu: View {
    let fileURL: URL
    @State private var apps: [URL] = []
    @State private var defaultApp: URL? = nil

    var body: some View {
        Menu("Open With") {
            // Default app first, bold
            if let defaultAppURL = defaultApp {
                Button {
                    NSWorkspace.shared.open(
                        [fileURL],
                        withApplicationAt: defaultAppURL,
                        configuration: NSWorkspace.OpenConfiguration()
                    ) { _, _ in }
                } label: {
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: defaultAppURL.path)
                                        .resized(to: NSSize(width: 16, height: 16)))
                        Text(defaultAppURL.deletingPathExtension().lastPathComponent)
                            .bold()
                    }
                }
                Divider()
            }
            // Remaining apps alphabetically
            ForEach(otherApps, id: \.self) { appURL in
                Button {
                    NSWorkspace.shared.open(
                        [fileURL],
                        withApplicationAt: appURL,
                        configuration: NSWorkspace.OpenConfiguration()
                    ) { _, _ in }
                } label: {
                    Label(appURL.deletingPathExtension().lastPathComponent,
                          image: /* app icon */)
                }
            }
            Divider()
            Button("Other...") {
                chooseApp(for: fileURL)
            }
        }
        .onAppear { loadApps() }
    }

    private func loadApps() {
        let all = NSWorkspace.shared.urlsForApplications(toOpen: fileURL)
        defaultApp = NSWorkspace.shared.urlForApplication(toOpen: fileURL)
        apps = all.filter { $0 != defaultApp }
                  .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
```

Note on icons in SwiftUI Menu: SwiftUI's `Button` inside a `.contextMenu` supports a `label:` closure accepting any `View`. Use `Image(nsImage:)` with the NSImage from `NSWorkspace.shared.icon(forFile:)`. Resize using `.resized(to:)` or `NSImage.size` property.

### Pattern 4: Quick Look via QLPreviewPanel

**What:** A lightweight `NSObject` subclass that conforms to `QLPreviewPanelDataSource` and can be injected into the responder chain when Quick Look is requested.

```swift
// QLPreviewHelper.swift
import AppKit
import QuickLookUI

class QLPreviewHelper: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    var previewURL: URL?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        return previewURL != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        return previewURL as QLPreviewItem?
    }
}
```

**Integrating into the responder chain:**

`QLPreviewPanel` traverses the NSResponder chain calling `acceptsPreviewPanelControl(_:)`. The standard integration point is `NSWindowController`, but in a SwiftUI app the window lifecycle is managed by SwiftUI. The minimal approach: call `panel.dataSource = helper` and `panel.delegate = helper` directly inside the action that shows the panel (bypassing full responder-chain integration), since Phase 9 will implement the full chain.

```swift
// In DatasetViewModel or a helper called by the context menu action
func quickLook(url: URL) {
    // Resign text view first responder to prevent NSTextView interception
    NSApp.keyWindow?.makeFirstResponder(nil)

    let panel = QLPreviewPanel.shared()!
    if panel.isVisible {
        panel.orderOut(nil)
    } else {
        quickLookHelper.previewURL = url
        panel.dataSource = quickLookHelper
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }
}
```

**Critical NSTextView interaction:** When `CaptionEditorView` (NSTextView) is first responder, NSTextView intercepts `QLPreviewPanel`'s responder chain lookup. Always call `NSApp.keyWindow?.makeFirstResponder(nil)` before showing the panel.

### Anti-Patterns to Avoid

- **Calling `QLPreviewPanel.shared()` without setting a dataSource first:** The panel will show an empty preview. Always set `panel.dataSource` before calling `makeKeyAndOrderFront`.
- **Using deprecated `NSWorkspace.urlsForApplications(toOpen: url)` Objective-C variant:** Use the Swift-native method `urlsForApplications(toOpen:)` available from macOS 12+.
- **Building the Open With app list synchronously on the main thread during menu construction:** `urlsForApplications(toOpen:)` is fast but populating app icons at menu-show time can cause a pause. Load in `onAppear` or lazily.
- **Using `NSWorkspace.open(withBundleIdentifier:)` deprecated API:** Use `open(_:withApplicationAt:configuration:completionHandler:)` instead.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Enumerate apps for file type | Custom LSCopyApplicationURLsForURL wrapper | `NSWorkspace.urlsForApplications(toOpen:)` | Official Swift API; handles UTType resolution automatically |
| Reveal file in Finder | Launching Finder manually | `NSWorkspace.activateFileViewerSelecting(_:)` | Handles Finder activation, window creation, and selection atomically |
| Open With mechanism | Custom subprocess or AppleScript | `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` | Handles sandboxing, Launch Services, and document handoff correctly |
| Quick Look preview | Custom image viewer panel | `QLPreviewPanel.shared()` | System panel with native animations, zoom, and navigation |
| Context menu on view | Custom NSMenu via NSViewRepresentable | SwiftUI `.contextMenu` modifier | Idiomatic SwiftUI; handles theme, platform, and accessibility automatically |

**Key insight:** NSWorkspace handles all sandbox escaping for launching other applications. A sandboxed app can open files in other apps via Launch Services without additional entitlements.

## Common Pitfalls

### Pitfall 1: NSTextView Hijacks QLPreviewPanel

**What goes wrong:** After clicking "Quick Look" in the context menu, the QLPreviewPanel either shows an empty panel or shows content from the NSTextView's text rather than the image file.
**Why it happens:** `NSTextView` has a private method `quickLookPreviewableItemsInRanges:` that answers `acceptsPreviewPanelControl` in the responder chain before any custom data source.
**How to avoid:** Before calling `panel.makeKeyAndOrderFront(nil)`, resign the text view's first responder status: `NSApp.keyWindow?.makeFirstResponder(nil)`.
**Warning signs:** QLPreviewPanel opens but shows wrong content or is blank.

### Pitfall 2: contextMenu vs onTapGesture Interference

**What goes wrong:** Folder right-click triggers the navigation `onTapGesture` instead of the context menu, or vice versa.
**Why it happens:** Gesture recognizer precedence issues in SwiftUI List views.
**How to avoid:** SwiftUI `.contextMenu` responds to right-click / Control+click and `.onTapGesture` responds to left-click — they do not conflict. Do not add a long-press gesture; that would conflict on iOS but not macOS.
**Warning signs:** Right-clicking a folder navigates to it instead of showing the menu.

### Pitfall 3: urlsForApplications(toOpen:) Returns Empty List

**What goes wrong:** The "Open With" submenu is empty.
**Why it happens:** The URL passed must be a `file://` URL pointing to an existing file, not a directory or non-existent path. If called before the file is scanned (before `pairs` is populated) or with a wrong URL scheme, it returns empty.
**How to avoid:** Always use `pair.imageURL` (which is a valid file URL from the directory scan). Verify the URL is `fileURL.isFileURL == true`.
**Warning signs:** Open With submenu appears but has no app items.

### Pitfall 4: Open in Terminal Fails in Sandboxed App

**What goes wrong:** "Open in Terminal" does nothing or crashes.
**Why it happens:** `Process` / `NSTask` cannot launch external executables in a sandboxed app. Direct `open(url:)` on Terminal.app may fail if Terminal's Info.plist does not declare the folder UTType.
**How to avoid:** Use `NSWorkspace.shared.open(folderURL, withApplicationAt: terminalURL)` where `terminalURL` is the URL to Terminal.app (found via `NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.terminal")`). This uses Launch Services and escapes the sandbox correctly. Do NOT use `Process` or `NSTask`.
**Warning signs:** Error logged "isn't allowed to open documents in Terminal" — this means wrong API used.

### Pitfall 5: App Icons Too Large in Menu

**What goes wrong:** Menu items with app icons show icons that are oversized (32px+), making the menu visually noisy.
**Why it happens:** `NSWorkspace.shared.icon(forFile:)` returns a 32x32 image by default.
**How to avoid:** Resize to 16x16 before setting as menu image: set `image.size = NSSize(width: 16, height: 16)`.
**Warning signs:** Open With submenu items are visually much taller than normal menu items.

### Pitfall 6: Security-Scoped Access and NSWorkspace

**What goes wrong:** `activateFileViewerSelecting` or `open(withApplicationAt:)` fails silently when the app's security-scoped bookmark session is not active.
**Why it happens:** The file URL must be accessible to pass to NSWorkspace.
**How to avoid:** The app currently keeps security-scoped access permanently active during the session via `startSecurityScopedAccess()`. This is already handled — no change needed. Both `activateFileViewerSelecting` and `open(withApplicationAt:)` work with URLs the app has sandbox access to.
**Warning signs:** Finder doesn't open, no error in logs.

## Code Examples

Verified patterns from official sources:

### Reveal in Finder
```swift
// Source: Apple Developer Documentation — activateFileViewerSelecting
NSWorkspace.shared.activateFileViewerSelecting([imageURL])
```

### Open Folder in Finder
```swift
// Source: Apple Developer Documentation — NSWorkspace.open(_:)
NSWorkspace.shared.open(folderURL)
```

### Open in Terminal (sandbox-safe)
```swift
// Source: Apple Developer Forums — confirmed pattern for sandboxed apps
if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.terminal") {
    NSWorkspace.shared.open(
        [folderURL],
        withApplicationAt: terminalURL,
        configuration: NSWorkspace.OpenConfiguration()
    ) { _, error in
        if let error { print("[openInTerminal] error:", error) }
    }
}
```

### Get Apps for Open With
```swift
// Source: Apple Developer Documentation — urlsForApplications(toOpen:)
// macOS 12+ Swift API
let apps: [URL] = NSWorkspace.shared.urlsForApplications(toOpen: imageFileURL)
let defaultApp: URL? = NSWorkspace.shared.urlForApplication(toOpen: imageFileURL)
```

### Open With Specific App
```swift
// Source: Apple Developer Documentation — open(_:withApplicationAt:configuration:completionHandler:)
NSWorkspace.shared.open(
    [imageURL],
    withApplicationAt: chosenAppURL,
    configuration: NSWorkspace.OpenConfiguration()
) { _, error in
    if let error { print("[openWith] error:", error) }
}
```

### SwiftUI Context Menu with Submenu
```swift
// Source: Apple Developer Documentation — contextMenu, Menu
HStack { /* row content */ }
.contextMenu {
    Button("Reveal in Finder") { ... }
    Menu("Open With") {
        Button("App Name") { ... }
    }
    Divider()
    Button("Quick Look") { ... }
}
```

### Minimal QLPreviewPanel Toggle
```swift
// Source: Apple Developer Documentation — QLPreviewPanel, QLPreviewPanelDataSource
// Resign first responder to prevent NSTextView hijack
NSApp.keyWindow?.makeFirstResponder(nil)
let panel = QLPreviewPanel.shared()!
if panel.isVisible {
    panel.orderOut(nil)
} else {
    panel.dataSource = previewHelper
    panel.reloadData()
    panel.makeKeyAndOrderFront(nil)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `NSWorkspace.urlsForApplications(toOpen: url: URL)` (ObjC) | `urlsForApplications(toOpen:)` Swift method | macOS 12 | Cleaner Swift API, no bridging |
| `launchApplication(at:options:configuration:)` | `openApplication(at:configuration:completionHandler:)` | macOS 11 deprecated old | Async completion handler |
| `open(withBundleIdentifier:...)` | `open(_:withApplicationAt:configuration:completionHandler:)` | macOS 11 | URL-based, not bundle ID |
| Custom responder chain setup for QLPreviewPanel | Same pattern (no new API) | Unchanged | Phase 9 adds spacebar; Phase 8 is minimal |

**Deprecated/outdated:**
- `NSWorkspace.open(withBundleIdentifier:files:additionalEventParamDescriptor:launchIdentifiers:)`: deprecated macOS 11, use `open(_:withApplicationAt:configuration:completionHandler:)`
- `launchApplication(at:options:configuration:)`: deprecated macOS 11
- `LSCopyApplicationURLsForURL`: C API, use `NSWorkspace.urlsForApplications(toOpen:)` instead

## Open Questions

1. **NSImage icons in SwiftUI Button labels inside contextMenu**
   - What we know: SwiftUI `Label` and `Button` inside `.contextMenu` accept `Image(nsImage:)` views
   - What's unclear: Whether NSImage icons from `icon(forFile:)` display correctly or need additional sizing/conversion on macOS 13/14
   - Recommendation: Use `Image(nsImage:)` with explicit `.resizable()` and `.frame(width: 16, height: 16)` for the app icon; fall back to SF Symbol if icon fails to load

2. **Default app bold text in SwiftUI Menu**
   - What we know: `.bold()` can be applied to `Text` inside a `Button` label in SwiftUI
   - What's unclear: Whether bold styling reliably renders inside `.contextMenu` on macOS (contextMenu uses AppKit NSMenu under the hood)
   - Recommendation: Apply `.bold()` and test; if it does not render, use a checkmark `Image(systemName: "checkmark")` prefix instead (Finder convention)

3. **QLPreviewPanel data source ownership for Phase 8**
   - What we know: Phase 9 will implement full QLPreviewPanel infrastructure; Phase 8 is deliberately minimal
   - What's unclear: Best place to own the `QLPreviewHelper` instance (ViewModel vs. ContentView @State)
   - Recommendation: Store as a property on `DatasetViewModel` (it's already `@MainActor`); this makes it easy for Phase 9 to extend

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (via `import Testing`) |
| Config file | lora-dataset.xcodeproj scheme — no separate config file |
| Quick run command | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests` |
| Full suite command | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CTXM-01 | File row right-click shows context menu | manual-only | N/A — SwiftUI context menu UI interaction | N/A |
| CTXM-02 | Folder row right-click shows context menu | manual-only | N/A — SwiftUI context menu UI interaction | N/A |
| CTXM-03 | "Reveal in Finder" / "Open in Finder" opens Finder | manual-only | N/A — requires OS interaction with Finder | N/A |
| CTXM-04 | "Open With" submenu populated correctly | unit (partial) | `xcodebuild test ... -only-testing:lora-datasetTests/OpenWithTests` | ❌ Wave 0 |
| CTXM-05 | "Quick Look" triggers QLPreviewPanel | manual-only | N/A — requires visual panel verification | N/A |

Note: Context menu display and OS-level Finder/Terminal integration cannot be meaningfully unit tested. The only automatable portion is the app-list-building logic for Open With (CTXM-04), which can test that `urlsForApplications(toOpen:)` returns non-empty results for a known image file and that sorting/filtering logic works correctly.

### Sampling Rate
- **Per task commit:** Run full suite: `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset`
- **Per wave merge:** Full suite green
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `lora-datasetTests/OpenWithTests.swift` — unit tests for app list building logic (CTXM-04)

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation — `NSWorkspace.activateFileViewerSelecting(_:)` — Reveal in Finder API
- Apple Developer Documentation — `NSWorkspace.urlsForApplications(toOpen:)` — Open With app enumeration
- Apple Developer Documentation — `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` — Open With specific app
- Apple Developer Documentation — `QLPreviewPanel` / `QLPreviewPanelDataSource` — Quick Look panel
- Apple Developer Documentation — SwiftUI `contextMenu(menuItems:)` — context menu modifier
- Apple Developer Documentation — SwiftUI `Menu` — nested submenu

### Secondary (MEDIUM confidence)
- [SerialCoder.dev — Enabling Selection, Double-Click and Context Menus in SwiftUI List on macOS](https://serialcoder.dev/text-tutorials/swiftui/enabling-selection-double-click-and-context-menus-in-swiftui-list-on-macos/) — contextMenu(forSelectionType:) pattern
- [DevGypsy.com — Quick Look with NSTableView and Swift (2023)](https://devgypsy.com/post/2023-06-06-quicklook-swift-tableview/) — QLPreviewPanel data source pattern
- Apple Developer Forums — NSTextView hijacks QLPreviewPanel responder chain (multiple threads)

### Tertiary (LOW confidence)
- Apple Developer Forums — "open in Terminal" from sandboxed app — `NSWorkspace.open(_:withApplicationAt:)` escapes sandbox via Launch Services; needs empirical validation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are official Apple frameworks, documented and stable
- Architecture: HIGH — `.contextMenu` on HStack is the obvious SwiftUI approach; confirmed by multiple sources
- Pitfalls: MEDIUM — NSTextView/QLPreviewPanel interaction verified by developer forum discussions; "Open in Terminal" sandbox behavior described in forums but should be validated empirically
- Open With icon/bold rendering: LOW — needs empirical test on macOS 14/15

**Research date:** 2026-03-15
**Valid until:** 2026-09-15 (stable Apple APIs; only major macOS version changes would affect this)
