# Project Research Summary

**Project:** LoRA Dataset Browser — v1.4 Native OS Integration
**Domain:** macOS native OS integration — SwiftUI + AppKit hybrid app
**Researched:** 2026-03-15
**Confidence:** HIGH

## Executive Summary

v1.4 adds three native macOS integration features to an existing SwiftUI + AppKit hybrid app: in-app Finder context menus on sidebar items, Quick Look preview panel (spacebar), and an NSTextView replacement for the caption editor. All three are well-understood AppKit/SwiftUI interop patterns. The recommended approach leans heavily on SwiftUI-native solutions where they exist (`.contextMenu` modifier, `.quickLookPreview` modifier) and falls back to the established `NSViewRepresentable + Coordinator` pattern — already proven in the codebase via `ZoomablePannableImage` — only where SwiftUI cannot reach the required capability.

The highest-value, lowest-risk feature is the NSTextView replacement: it follows an identical pattern to the existing code, delivers spell check and grammar for free, and has no interaction effects with the other two features. Context menus are purely additive and require zero new files. Quick Look is the only feature with meaningful integration complexity: `QLPreviewPanel` requires a responder-chain anchor that does not exist naturally in a pure SwiftUI window, and NSTextView's private responder chain behavior will silently intercept the panel if focus is not cleared first. These risks are well-documented and have known solutions.

The key risk to avoid is scope drift: "Finder context menus" colloquially suggests two entirely different implementations — an in-app SwiftUI context menu (correct, minimal effort) versus a FinderSync app extension (wrong direction, separate sandbox process, security-scoped access does not cross process boundaries). v1.4 implements in-app menus only.

## Key Findings

### Recommended Stack

The existing stack (SwiftUI + AppKit, `NSViewRepresentable`, MVVM, security-scoped bookmarks) requires only three additions for v1.4. No third-party dependencies are needed. The `QuickLookUI` framework (`import Quartz`) and `NSTextView` are built-in AppKit. SwiftUI's `.contextMenu` modifier handles menu construction without touching raw `NSMenu`.

**Core technologies:**
- `QuickLookUI` / `QLPreviewPanel`: floating Quick Look panel — the only official API for the native macOS floating panel; no alternative exists
- `NSTextView` (AppKit): full-featured caption editor — required to unlock spell check, grammar check, system dictionary lookup, and language detection unavailable in SwiftUI `TextEditor`
- SwiftUI `.contextMenu` modifier: right-click menus on sidebar rows — native SwiftUI; sufficient for all required actions with no AppKit boilerplate
- SwiftUI `.quickLookPreview($url)` modifier (macOS 13+): preferred QL integration — handles `QLPreviewPanel` lifecycle automatically; use only if the responder chain anchor issue is resolved via this path; see Architecture caveat
- `NSWorkspace.shared.activateFileViewerSelecting(_:)`: Reveal in Finder — one-line call, no entitlements required from sandboxed app

**Critical version notes:**
- SwiftUI `.onKeyPress(.space)` requires macOS 14+; fallback to `NSViewRepresentable` key capture for macOS 13 targets
- SwiftUI `.quickLookPreview` is macOS 13+; manual responder chain pattern is the fallback

### Expected Features

The v1.4 feature set is scoped tightly. All must-have items are either one-line API calls or follow the established coordinator pattern; none require novel architecture.

**Must have (table stakes for v1.4):**
- Right-click context menu on sidebar file rows — "Reveal in Finder", "Quick Look" actions
- Right-click context menu on sidebar folder rows — "Open in Finder" action
- Spacebar triggers Quick Look preview panel for the selected image file
- Spacebar again (or Escape) dismisses the Quick Look panel
- NSTextView replaces SwiftUI `TextEditor` — continuous spell checking and grammar checking enabled
- Right-click "Look Up" in caption text (free with NSTextView — no code required)
- Edit > Spelling and Grammar menu wired automatically (free with NSTextView as first responder)

**Should have (polish, low effort since NSTextView is in place):**
- Grammar checking (`isGrammarCheckingEnabled = true`) — one property alongside spell check
- Auto-language detection — free with NSTextView / NSSpellChecker
- Folder vs. file distinction in context menu ("Open in Finder" for folders, "Reveal in Finder" for files) — matches Finder's exact behavior

**Defer (v2+):**
- Services submenu in context menus — requires full AppKit sandwich pattern (`NSViewRepresentable` + `NSServicesMenuRequestor`); high complexity, low value for solo developer
- FinderSync extension (real Finder context menus) — separate sandbox process, separate app extension target, security-scoped access does not transfer
- Batch Quick Look cycling — niche, adds responder complexity

**Explicitly omit:**
- "Move to Trash" in context menu — destructive file operation without undo; out of scope for a caption editor
- Quick Look preview of `.txt` caption files — redundant; caption text is already inline in the editor

### Architecture Approach

The architecture adds minimal surface area to the existing codebase. Only one new file (`NativeTextEditor.swift`) is created. Two existing files are modified (`ContentView.swift`, `DatasetViewModel.swift`). The `DatasetViewModel` gains a single new published property (`previewURL: URL?`) to drive Quick Look. Context menus are pure view-layer additions. No new view model, no new coordinator pattern beyond what already exists.

**Major components:**
1. `NativeTextEditor` (new `NSViewRepresentable`) — wraps `NSScrollView + NSTextView`; follows the identical coordinator pattern of `ZoomablePannableImage`; replaces `TextEditor` in `DetailView`
2. `.contextMenu` modifiers on `FolderNodeView` and file-row `HStack` in `ContentView` — purely declarative; call `NSWorkspace` directly for OS-delegation actions, call `DatasetViewModel` methods for state-mutating actions
3. `.quickLookPreview($vm.previewURL)` modifier on `NavigationSplitView` + `vm.previewURL: URL?` — binding-driven panel; spacebar and context menu "Quick Look" both set/nil this property

**Build order dictated by integration dependencies:**
1. `NativeTextEditor` — self-contained, no interactions with other v1.4 features
2. Context menus — self-contained, establishes the `previewURL` property used by Quick Look
3. Quick Look — built last so NSTextView/QLPreviewPanel focus conflict can be tested in full integration

### Critical Pitfalls

1. **QLPreviewPanel intercepted by NSTextView focus** — `NSTextView` has a private `quickLookPreviewableItemsInRanges:` method that claims panel control before your controller, producing a blank or wrong panel. Resolution: call `window?.makeFirstResponder(nil)` before opening the panel; design spacebar to trigger only from the sidebar (not the text editor), which avoids the conflict by construction.

2. **NSTextView cursor jump in `updateNSView`** — unconditionally setting `textView.string = text` in every `updateNSView` call resets the cursor to end-of-text after each keystroke. Guard with `if tv.string != text` and an `isEditing` coordinator flag (`true` between `textDidBeginEditing` and `textDidEndEditing`); only push external changes into the view when the user is not actively editing.

3. **NSTextView undo chain broken by SwiftUI state sync** — if `updateNSView` sets `textView.string` while the user is mid-edit, NSTextView's undo history is destroyed. The `isEditing` guard from pitfall 2 prevents this. Never remove and re-add `NSTextView` and `TextEditor` simultaneously during transition — swap in a single commit.

4. **QLPreviewPanel responder chain anchor missing in SwiftUI windows** — SwiftUI `WindowGroup` has no `NSWindowController`; the three `NSResponder` methods (`acceptsPreviewPanelControl`, `beginPreviewPanelControl`, `endPreviewPanelControl`) must be implemented on an `NSView` subclass used via `NSViewRepresentable`, or on an `AppDelegate`-owned controller inserted into the chain. Attempting to use the SwiftUI `.quickLookPreview` modifier directly may show a sheet instead of the floating panel — verify macOS-target behavior before committing to this path.

5. **Context menu hit area on List rows** — SwiftUI's `.contextMenu` on macOS `List` rows only activates on the narrow text region, not the full row width, on Sonoma+. Fix: ensure all sidebar rows have `.frame(maxWidth: .infinity, alignment: .leading)` and `.contentShape(Rectangle())` — both already present in `FolderNodeView` per existing codebase guidance.

## Implications for Roadmap

Based on research, v1.4 is a single-milestone deliverable. The three features are independent enough to build sequentially within one phase, but their integration interaction (NSTextView + QLPreviewPanel focus) justifies the explicit build order below.

### Phase 1: NSTextView Caption Editor

**Rationale:** Purely additive with no interaction effects on the rest of the app. Validates the coordinator pattern, establishes the `isEditing` guard, and sets up undo correctly before Quick Look integration introduces responder-chain complexity. If this phase is done correctly, it de-risks pitfalls 2, 3, and the NSTextView half of pitfall 1.

**Delivers:** `NativeTextEditor.swift` replacing `TextEditor`; spell check, grammar check, "Look Up", Edit > Spelling and Grammar, auto-language detection

**Addresses:** All spell/grammar/dictionary features from the must-have list

**Avoids:** Cursor jump (pitfall 2), undo chain corruption (pitfall 3), spell check silently off by default (UX pitfall)

**Key implementation notes:**
- Set all text-system flags in `makeNSView` only — never in `updateNSView`
- Use `isEditing` coordinator flag to guard `updateNSView` string replacement
- Set `isAutomaticQuoteSubstitutionEnabled = false` and `isAutomaticDashSubstitutionEnabled = false` — LoRA captions are training data; smart punctuation corrupts tokens
- Remove `TextEditor` in the same commit that adds `NativeTextEditor` — never run both simultaneously

### Phase 2: Finder Context Menus

**Rationale:** Self-contained view-layer addition. Establishes `vm.previewURL: URL?` on the ViewModel, which Quick Look (Phase 3) depends on. No new files needed.

**Delivers:** Right-click context menus on folder rows and file rows in the sidebar; Reveal in Finder, Open in Finder, Quick Look (stub — calls `vm.previewURL = pair.imageURL`), Copy Path

**Addresses:** Context menu table-stakes features; folder vs. file action distinction

**Avoids:** FinderSync scope creep (pitfall 4 from PITFALLS.md); context menu hit area bug (pitfall 5)

**Key implementation notes:**
- In-app SwiftUI `.contextMenu` only — do not create a FinderSync extension target under any circumstance
- Add `.contentShape(Rectangle())` to all rows if not already present on file rows
- Context menu actions: call `NSWorkspace` directly for OS-delegation (Reveal in Finder, Open in Finder); call `vm` methods for state changes

### Phase 3: Quick Look Preview

**Rationale:** Built last because it has integration risk with both prior phases: it needs `vm.previewURL` (Phase 2) and must coexist safely with `NativeTextEditor` focus (Phase 1). Building last maximizes integration test surface.

**Delivers:** Spacebar triggers `QLPreviewPanel` for the selected image; panel toggle (press again to dismiss); context menu "Quick Look" item delegates to same mechanism

**Addresses:** Quick Look table-stakes features; spacebar muscle-memory expectation

**Avoids:** NSTextView focus intercepting the panel (pitfall 1); responder chain anchor missing in SwiftUI window (pitfall 3)

**Key implementation notes:**
- Decide early whether `.quickLookPreview($vm.previewURL)` (macOS 13+ modifier path) correctly produces a floating panel on the target OS, or whether the manual `NSResponder` subclass path is required — verify before writing more than a prototype
- If using the modifier path, spacebar should call `vm.previewURL = (vm.previewURL == nil) ? pair.imageURL : nil` via `.onKeyPress(.space)` on the sidebar
- If using the manual responder path, implement the three control methods on a dedicated `NSViewRepresentable` shim inserted into the hierarchy; never implement them on `ContentView` directly
- Always call `window?.makeFirstResponder(nil)` before `makeKeyAndOrderFront` to clear NSTextView focus
- Implement `endPreviewPanelControl` and nil out delegate/dataSource — do not skip cleanup

### Phase Ordering Rationale

- NSTextView first because it eliminates the responder-chain uncertainty for subsequent phases; once `NativeTextEditor` is in place the team knows exactly how it behaves as a first responder
- Context menus second because they are the simplest addition and establish `vm.previewURL` without any new interaction risks
- Quick Look last because it is the only feature that depends on the others being stable and correctly tested first
- This order also reflects implementation risk: descending complexity means early phases build confidence before the highest-risk integration

### Research Flags

Phases likely needing attention during implementation:

- **Phase 3 (Quick Look):** The `.quickLookPreview` modifier vs. manual responder chain decision must be validated empirically on the target macOS version before committing to an implementation path. ARCHITECTURE.md recommends the modifier; PITFALLS.md notes it may produce a sheet rather than a floating panel. This is the one unresolved uncertainty in the research.

Phases with standard patterns — proceed without additional research:

- **Phase 1 (NSTextView):** Pattern is identical to `ZoomablePannableImage`, which already works. All pitfalls are documented and have known fixes.
- **Phase 2 (Context Menus):** SwiftUI `.contextMenu` on `List` rows is well-documented with a known hit-area fix. No research gaps.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM | APIs verified against official docs and 2023-2024 community sources; one known limitation (grammar checking depth) is LOW confidence but does not affect the implementation decision |
| Features | HIGH | AppKit/SwiftUI behaviors are stable and well-documented; feature scope is narrow and unambiguous |
| Architecture | HIGH | All three integration areas verified against Apple docs and multiple community implementations; build order is grounded in documented dependencies |
| Pitfalls | HIGH | NSTextView and QLPreviewPanel pitfalls confirmed by multiple independent sources; context menu hit-area bug confirmed on Sonoma; security-scoped bookmark sandbox boundary confirmed by Apple staff on Developer Forums |

**Overall confidence:** HIGH

### Gaps to Address

- **`.quickLookPreview` modifier vs. manual responder chain for macOS target:** Research consensus favors the modifier, but one source (PITFALLS.md) notes it may not show the floating `QLPreviewPanel` on macOS. Validate empirically in a small prototype at the start of Phase 3 before writing production code. If the modifier produces a sheet or popover, fall back to the manual `NSViewRepresentable` responder shim documented in STACK.md.
- **Grammar checking depth:** `isGrammarCheckingEnabled = true` activates the public API surface only. Whether this matches user expectations for grammar feedback is unknown. LOW impact — enable it as documented; user feedback will determine whether it is useful enough to surface in UI.

## Sources

### Primary (HIGH confidence)

- [QLPreviewPanel — Apple Developer Documentation](https://developer.apple.com/documentation/quicklookui/qlpreviewpanel) — responder chain control pattern
- [Quick Look with NSTableView and Swift (2023) — DevGypsy](https://devgypsy.com/post/2023-06-06-quicklook-swift-tableview/) — complete Swift responder chain implementation
- [Including Services in contextual menus in SwiftUI — Wade Tregaskis](https://wadetregaskis.com/including-services-in-contextual-menus-in-swiftui/) — Services limitation and AppKit sandwich pattern
- [Apple Developer Forums: FinderSync extension sandbox boundary](https://developer.apple.com/forums/thread/677665) — security-scoped access does not cross processes (Apple staff confirmed)
- [Apple Developer Forums: Finder Sync Extension sandboxed access](https://developer.apple.com/forums/thread/717098) — `startAccessingSecurityScopedResource` in extension context
- [Enabling Selection, Double-Click and Context Menus in SwiftUI List — SerialCoder.dev](https://serialcoder.dev/text-tutorials/swiftui/enabling-selection-double-click-and-context-menus-in-swiftui-list-on-macos/)
- [Apple Developer Forums: How do I update state in NSViewRepresentable](https://developer.apple.com/forums/thread/125920) — updateNSView cursor/state pitfalls

### Secondary (MEDIUM confidence)

- [QuickLook + TextView Trouble — Michael Berk](https://mberk.com/posts/QuickLook+TextViewTrouble/) — NSTextView/QLPreviewPanel responder chain conflict
- [Small click areas in SwiftUI contextMenu with List — Cocoa Switch (2023)](https://www.cocoaswitch.com/2023/12/09/small-click-areas.html) — hit area fix
- [MacEditorTextView gist — unnamedd](https://gist.github.com/unnamedd/6e8c3fbc806b8deb60fa65d6b9affab0) — NSViewRepresentable NSTextView reference implementation
- [Using NSTextView in SwiftUI — Blue Lemon Bits](https://bluelemonbits.com/2021/11/14/using-nstextview-in-swiftui/) — undo manager, spell check, delegate wiring
- [How does NSTextView invoke grammar checking internally — Swift Forums](https://forums.swift.org/t/how-does-nstextview-invoke-grammar-checking-internally/84832) — grammar depth limitation

### Tertiary (LOW confidence)

- Grammar checking public API depth — assessed via Swift Forums thread; actual user-visible quality requires empirical validation

---
*Research completed: 2026-03-15*
*Ready for roadmap: yes*
