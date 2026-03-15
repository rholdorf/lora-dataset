# Stack Research

**Domain:** macOS native OS integration — Finder context menus, Quick Look panel, full NSTextView
**Researched:** 2026-03-15
**Confidence:** MEDIUM (APIs verified via official docs and 2023-2024 community sources; one known limitation with grammar checking depth)

---

## Scope

This is a **subsequent milestone** research file. Only stack additions and changes for v1.4 features are documented here. The existing validated base (SwiftUI + AppKit, NSViewRepresentable, MVVM, security-scoped bookmarks) is not re-litigated.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `QuickLookUI` framework | macOS built-in | QLPreviewPanel integration | The only official API for the floating Quick Look panel on macOS. No third-party alternative exists for this native panel. |
| `NSTextView` (AppKit) | macOS built-in | Full-featured text editing | Required to unlock spell check, grammar check, system dictionary lookup, and language detection — features unavailable in SwiftUI's `TextEditor`. |
| SwiftUI `.contextMenu` modifier | macOS 12+ | Right-click context menus on sidebar rows | Native SwiftUI. Sufficient for "Reveal in Finder", "Open with", and custom app actions. No AppKit required for the menu itself. |

### Supporting APIs

| API / Class | Framework | Purpose | When to Use |
|-------------|-----------|---------|-------------|
| `QLPreviewPanel.shared()` | QuickLookUI | Singleton panel showing file preview | Toggle on spacebar press from sidebar or file list |
| `QLPreviewPanelDataSource` | QuickLookUI | Provide URLs to the panel | Implement on the window controller / NSResponder in the responder chain |
| `QLPreviewPanelDelegate` | QuickLookUI | Source frame for zoom animation | Optional but improves animation quality |
| `NSTextView` | AppKit | Replaces `TextEditor` | Wrap in `NSViewRepresentable` — same pattern as `ZoomablePannableImage` |
| `NSTextViewDelegate` | AppKit | Receive text change callbacks | Used in Coordinator, replaces `Binding<String>` in TextEditor |
| `NSScrollView` | AppKit | Required container for NSTextView | NSTextView must be embedded in an NSScrollView for correct sizing |
| `NSWorkspace.shared.activateFileViewerSelecting(_:)` | AppKit | Reveal file in Finder | Use in context menu "Reveal in Finder" action |
| `NSWorkspace.shared.open(_:)` | AppKit | Open file with default app | Use in context menu "Open with Default App" action |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode Interface Builder (optional) | Connecting window controller responder | QLPreviewPanel responder chain works without IB — Swift extension on `NSViewController` suffices |

---

## Integration Points with Existing Code

### 1. Quick Look — QLPreviewPanel

**How it works:** QLPreviewPanel walks the NSResponder chain asking each responder `acceptsPreviewPanelControl(_:)`. The first responder returning `true` takes ownership and configures the panel via `beginPreviewPanelControl(_:)`.

**Where to integrate:** Add a Swift extension on the existing `ContentView`'s hosting `NSWindowController`, or more pragmatically, create an `NSViewController` subclass using `NSViewControllerRepresentable` and put the responder chain methods there. The simplest path is adding the three methods to the `AppDelegate` or a dedicated `QLController` object that is inserted into the responder chain.

**Required import:** `import Quartz`

**Three methods that must be implemented:**
```swift
override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
    return true
}

override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
    panel.delegate = self
    panel.dataSource = self
}

override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
    // clear references
}
```

**Spacebar handling:** The sidebar `List` is a SwiftUI view, so it doesn't naturally subclass `NSView` for key overrides. The cleanest approach is to use SwiftUI's `.onKeyPress(.space)` (macOS 14+) or a focused `Button` with keyboard shortcut `.space`. If targeting macOS 13 and below, wrap the list in an `NSViewRepresentable` that subclasses `NSView` and overrides `keyDown`.

**Critical gotcha — NSTextView conflict (MEDIUM confidence):** When an `NSTextView` has focus, it intercepts the responder chain and takes QLPreviewPanel control for its own Quick Look on text ranges. This results in an empty or wrong Quick Look panel. The documented workarounds are:
1. Ensure the sidebar (not the text view) has focus before triggering Quick Look — user must click sidebar before pressing spacebar
2. Re-set `panel.dataSource = self` after the panel becomes visible (via `panelDidBecomeKey`)
3. Do not subclass or override the private `quickLookPreviewableItems(inRanges:)` method — it is undocumented and App Store reviewers may flag it

Source: [QuickLook + TextView Trouble — Michael Berk](https://mberk.com/posts/QuickLook+TextViewTrouble/)

---

### 2. NSTextView Replacement for TextEditor

**Pattern:** Same `NSViewRepresentable` pattern already used in `ZoomablePannableImage`. The Coordinator becomes an `NSTextViewDelegate`.

**NSTextView must be embedded in NSScrollView:**
```swift
let scrollView = NSScrollView()
let textView = NSTextView()
scrollView.documentView = textView
// return scrollView from makeNSView
```

**Properties to set in `makeNSView`:**
```swift
textView.isContinuousSpellCheckingEnabled = true
textView.isGrammarCheckingEnabled = true
textView.isAutomaticSpellingCorrectionEnabled = true
textView.isAutomaticTextReplacementEnabled = true
textView.isAutomaticQuoteSubstitutionEnabled = true
textView.isAutomaticDashSubstitutionEnabled = true
textView.isAutomaticLinkDetectionEnabled = false   // not useful for captions
textView.allowsUndo = true
textView.usesFontPanel = false   // not needed for plain caption text
textView.isRichText = false      // plain text only, matches caption files
textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
```

**Known issue with `isContinuousSpellCheckingEnabled`:** SwiftUI may reset this property to `false` when `updateNSView` is called. The fix is to guard against re-setting in `updateNSView` — only configure these flags once in `makeNSView`, never in `updateNSView`. Do not include them in the update path.

**Grammar checking depth limitation (LOW confidence):** The public `NSSpellChecker` API does not surface the same grammar analysis depth as TextEdit's internal implementation. Setting `isGrammarCheckingEnabled = true` activates what the public API exposes (subject-verb agreement and similar), which is the correct approach and covers most use cases. Do not attempt to call private grammar APIs.

**Receiving text changes via Coordinator:**
```swift
func textDidChange(_ notification: Notification) {
    guard let tv = notification.object as? NSTextView else { return }
    parent.text = tv.string
}
```

**Language detection:** Automatic — the macOS text system performs language detection when spell checking is enabled. No additional configuration is needed.

---

### 3. Finder Context Menus (Sidebar + File List)

**Use SwiftUI's `.contextMenu` modifier directly.** This is sufficient for the required actions (reveal in Finder, open with default app, copy path). No AppKit NSMenu subclass is needed.

Apply it to each `FolderNodeView` and each file row in the `ForEach` loop inside `ContentView`:

```swift
.contextMenu {
    Button("Reveal in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }
    Button("Open in Default App") {
        NSWorkspace.shared.open(node.url)
    }
    Divider()
    Button("Copy Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.url.path, forType: .string)
    }
}
```

**Note on Services submenu:** SwiftUI's `.contextMenu` does not include the system Services submenu. This is a known limitation. For a dataset management tool used solo, this omission is acceptable. If Services (e.g., "Open in Terminal") become required, the workaround requires an "AppKit sandwich" using `NSViewRepresentable` + `NSHostingView` + `NSServicesMenuRequestor` — significant complexity with marginal value.

Source: [Including Services in contextual menus in SwiftUI — Wade Tregaskis](https://wadetregaskis.com/including-services-in-contextual-menus-in-swiftui/)

**Known issue — small click areas in SwiftUI List:** `.contextMenu` on SwiftUI List rows on macOS sometimes only triggers on a narrow hit area, not the full row width. The fix is to ensure the row view has `.frame(maxWidth: .infinity)` and `.contentShape(Rectangle())` — both already present in the current `FolderNodeView`.

Source: [Small click areas in SwiftUI contextMenu with List — Cocoa Switch](https://www.cocoaswitch.com/2023/12/09/small-click-areas.html)

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| SwiftUI `.contextMenu` | AppKit `NSMenu` + `NSViewRepresentable` | Only if Services submenu is a hard requirement |
| `QLPreviewPanel` responder chain | SwiftUI `.quickLookPreview` modifier (macOS 13+) | `.quickLookPreview` opens a modal sheet, not the floating panel. Use it if the Finder-panel behavior (floating, dismissable with spacebar) is not required. |
| `NSTextView` in `NSViewRepresentable` | SwiftUI `TextEditor` | Keep `TextEditor` if spell check/grammar is not needed — it is simpler and avoids the QLPreviewPanel conflict |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `quickLookPreviewableItems(inRanges:)` override | Undocumented private API, App Store review risk, may break on OS updates | Accept the focus-dependency workaround for QL + NSTextView conflict |
| `NSSharingService` or `NSSharingServicePicker` | For sharing to other apps, not for the Finder context menu pattern | `NSWorkspace` for Finder operations |
| Third-party rich text editor libraries (e.g. STTextView, RichTextKit) | Over-engineered for plain text captions. Adds a dependency for features not needed. | Plain `NSTextView` with `isRichText = false` |
| Setting spell-check flags in `updateNSView` | Causes SwiftUI to repeatedly reset `isContinuousSpellCheckingEnabled` to `false` | Set all text system flags once in `makeNSView` only |

---

## Version Compatibility

| Feature | Minimum macOS | Notes |
|---------|--------------|-------|
| `QLPreviewPanel` / `QuickLookUI` | macOS 10.6 | Stable, no version concerns |
| `NSTextView` spell/grammar properties | macOS 10.5 | All properties used are long-stable |
| SwiftUI `.contextMenu` on `List` rows | macOS 12.0 | Works reliably from macOS 12+ |
| SwiftUI `.onKeyPress(.space)` | macOS 14.0 | If targeting macOS 13, use `NSViewRepresentable` key capture instead |
| `contextMenu(forSelectionType:menu:primaryAction:)` | macOS 13.0 | More powerful than plain `.contextMenu`; optional upgrade |

---

## Sources

- [QLPreviewPanel — Apple Developer Documentation](https://developer.apple.com/documentation/quicklookui/qlpreviewpanel) — responder chain control pattern
- [Quick Look with NSTableView and Swift (2023) — DevGypsy](https://devgypsy.com/post/2023-06-06-quicklook-swift-tableview/) — complete Swift implementation, HIGH confidence
- [QuickLook + TextView Trouble — Michael Berk](https://mberk.com/posts/QuickLook+TextViewTrouble/) — NSTextView/QLPreviewPanel conflict, MEDIUM confidence (paywalled, summarized via search)
- [Including Services in contextual menus in SwiftUI — Wade Tregaskis](https://wadetregaskis.com/including-services-in-contextual-menus-in-swiftui/) — Services submenu limitation and workaround, HIGH confidence
- [How does NSTextView invoke grammar checking internally — Swift Forums](https://forums.swift.org/t/how-does-nstextview-invoke-grammar-checking-internally/84832) — grammar depth limitation, MEDIUM confidence
- [Small click areas in SwiftUI contextMenu with List — Cocoa Switch (2023)](https://www.cocoaswitch.com/2023/12/09/small-click-areas.html) — hit area fix, MEDIUM confidence
- [MacEditorTextView gist — unnamedd](https://gist.github.com/unnamedd/6e8c3fbc806b8deb60fa65d6b9affab0) — NSTextView NSViewRepresentable reference implementation, MEDIUM confidence
- [Enabling Selection, Double-Click and Context Menus in SwiftUI List — SerialCoder.dev](https://serialcoder.dev/text-tutorials/swiftui/enabling-selection-double-click-and-context-menus-in-swiftui-list-on-macos/) — List context menu pattern, MEDIUM confidence

---
*Stack research for: macOS native OS integration (LoRA Dataset Browser v1.4)*
*Researched: 2026-03-15*
