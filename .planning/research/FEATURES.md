# Feature Research

**Domain:** Native macOS OS integration — Finder context menus, Quick Look preview, NSTextView
**Researched:** 2026-03-15
**Confidence:** HIGH (AppKit/SwiftUI behaviors are stable, well-documented, and cross-verified)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that macOS users assume exist in any native file-browsing app. Missing these makes the app feel unpolished or broken compared to Finder.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Right-click context menu on sidebar items | Every macOS file browser exposes actions via right-click; absence is jarring | MEDIUM | SwiftUI `.contextMenu(forSelectionType:menu:primaryAction:)` modifier handles this cleanly on macOS 13+ |
| "Reveal in Finder" / "Show in Finder" menu item | Standard action in every macOS file-aware app (Xcode, VS Code, etc.); users expect to jump to Finder from any file reference | LOW | `NSWorkspace.shared.activateFileViewerSelecting([url])` — one line |
| Quick Look with spacebar | Spacebar = Quick Look is a muscle-memory reflex for Mac users who use Finder; any app showing files without spacebar preview feels incomplete | MEDIUM | Requires intercepting `keyDown` (spacebar) and showing `QLPreviewPanel.shared()`; needs responder chain wiring |
| Quick Look panel toggles on second spacebar press | Users expect spacebar to be a toggle — press once to open, press again to close; one-way-only open breaks the mental model | LOW | `QLPreviewPanel.shared().isVisible` check inside the toggle handler |
| Spell check while typing (red underlines) | Users expect any text input field in a macOS app to have spell check; SwiftUI TextEditor gives this, but only partially | LOW | `NSTextView.isContinuousSpellCheckingEnabled = true` (must be set explicitly; default is false) |
| Right-click "Look Up" in text | Standard NSTextView behavior in every macOS text field including Safari, Mail, TextEdit; users three-finger-tap or right-click expecting "Look Up" | LOW | Free with NSTextView — appears automatically in the contextual menu when text is selected |
| Edit > Spelling and Grammar menu integration | macOS apps have a system-provided Edit menu section for spell/grammar checking; users navigate via menu bar | LOW | Free with NSTextView — the Edit menu items wire up automatically when NSTextView is first responder |

### Differentiators (Competitive Advantage)

Features that go beyond the baseline to make the app feel more intentional and polished. Relevant because this is a solo developer's daily-driver tool.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Context menu on image files includes "Quick Look" item | Reinforces discoverability: right-clicking an image file also offers Quick Look, not just the spacebar shortcut | LOW | One additional menu item in the image file context menu; delegates to the same QLPreviewPanel toggle |
| Context menu on folders includes "Open in Finder" vs "Reveal in Finder" distinction | Folders should "open" in Finder (shows folder contents), files should "reveal" (highlights the file); matches Finder's own behavior exactly | LOW | Two separate `NSWorkspace` calls: `open(_:)` for folders, `activateFileViewerSelecting` for files |
| Grammar checking alongside spell check | Catches grammatical issues in captions, not just misspellings; useful for caption quality | LOW | `NSTextView.isGrammarCheckingEnabled = true` — one additional property alongside spell check |
| Edit > Substitutions integration (smart quotes, dashes, text replacement) | System-level text substitution preferences are respected; feels fully native | LOW | Free with NSTextView when substitutions properties are left at system defaults — no special code needed |
| NSTextView auto-language detection | System detects caption language and applies correct spell-check dictionary automatically | LOW | Free with NSTextView via `NSSpellChecker.automaticallyIdentifiesLanguages` — enabled by default |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Smart quotes/auto-correct enabled by default for caption editing | Feels polished; macOS enables it in TextEdit | Captions are training data — smart quotes (`"` `"`) corrupt prompts that expect straight quotes (`"`); auto-correct changes intended tokens | Leave substitutions at system defaults but document that users should disable smart quotes in System Preferences if they type quotes; or explicitly disable `isAutomaticQuoteSubstitutionEnabled` on the NSTextView |
| Full Services submenu in context menu | Power users use Services for text manipulation, sharing, etc. | Requires abandoning SwiftUI's `.contextMenu` modifier entirely and using an NSViewRepresentable AppKit sandwich pattern with `allowsContextMenuPlugIns`; significant implementation complexity for a tool used by a solo developer | For v1.4, omit Services; note it as a future enhancement if the app gains broader users |
| "Move to Trash" in context menu | Natural for file management | This app is a caption editor, not a file manager; destructive file operations introduce accidental data loss risk with no undo | Omit entirely; if deletion is ever needed, add it as a deliberate future feature with confirmation dialogs |
| Quick Look for the caption .txt file alongside the image | Seems thorough — preview both assets | Quick Look for plain text .txt files in QLPreviewPanel is underwhelming (shows raw text); the caption editor already shows text inline; redundant and confusing | Let spacebar trigger Quick Look only for the image file; caption text is already visible in the editor |

---

## Feature Dependencies

```
[Sidebar right-click context menu]
    └──requires──> [SwiftUI List with selection binding] (already exists in v1.3)
    └──requires──> [File URL available per sidebar item] (already exists)

[Quick Look panel (spacebar)]
    └──requires──> [keyDown event interception on the sidebar list]
                       └──requires──> [NSView subclass OR SwiftUI onKeyPress (macOS 14+)]
    └──requires──> [QLPreviewPanel data source providing the selected file URL]

["Reveal in Finder" context menu item]
    └──requires──> [File URL available per sidebar item] (already exists)

[NSTextView caption editor]
    └──requires──> [NSViewRepresentable wrapper] (pattern already established with ZoomablePannableImage)
    └──enhances──> [Spell check, grammar, Look Up, substitutions] (all free once NSTextView is in place)
    └──conflicts──> [SwiftUI TextEditor] (replace, do not augment)

[Quick Look "Quick Look" context menu item]
    └──requires──> [Quick Look panel (spacebar)] (same underlying toggle; reuses it)
```

### Dependency Notes

- **NSTextView requires NSViewRepresentable:** The existing codebase already uses this pattern for `ZoomablePannableImage`, so the team has a working template. The NSTextView wrapper will follow the same coordinator pattern.
- **Quick Look spacebar requires keyDown interception:** SwiftUI List does not natively expose `keyDown`. On macOS 14+, `.onKeyPress(.space)` may work. On macOS 13, an NSViewRepresentable wrapping an NSTableView subclass (or an `NSHostingView`-based shim) is needed. This is the highest-complexity item in the milestone.
- **NSTextView conflicts with SwiftUI TextEditor:** The caption editor must be replaced, not augmented. Running both simultaneously creates first-responder conflicts and duplicate Edit menu wiring.
- **Spell check settings must be set explicitly:** `isContinuousSpellCheckingEnabled` defaults to `false` on NSTextView; the app must set it to `true`. This is a known developer footgun — do not assume NSTextView enables spell checking automatically.

---

## MVP Definition

### Launch With (v1.4)

Minimum set to call this milestone complete.

- [ ] Right-click context menu on sidebar file items — "Reveal in Finder" and "Quick Look" actions
- [ ] Right-click context menu on sidebar folder items — "Open in Finder" action
- [ ] Spacebar triggers Quick Look preview panel for the selected image file
- [ ] Second spacebar press (or Escape) closes the Quick Look panel
- [ ] NSTextView replaces SwiftUI TextEditor for caption editing
- [ ] Continuous spell checking enabled (red underlines while typing)
- [ ] Grammar checking enabled
- [ ] Right-click "Look Up" in caption text (free with NSTextView)
- [ ] Edit > Spelling and Grammar menu wired up (free with NSTextView as first responder)

### Add After Validation (v1.x)

- [ ] Services submenu in context menus — add if usage expands beyond solo developer; requires AppKit sandwich pattern (high effort, low value for one user)
- [ ] Substitutions submenu control in the app UI — add if smart-quotes issues surface in practice

### Future Consideration (v2+)

- [ ] Finder Extension (FinderSync) to add context menu items into the real Finder — out of scope; requires a separate app extension target and code signing entitlement
- [ ] Batch Quick Look (multiple selection cycling) — niche, adds complexity
- [ ] Custom "Look Up" data source (e.g., LoRA training glossary) — interesting but speculative

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Reveal in Finder (context menu) | HIGH | LOW | P1 |
| Quick Look (spacebar) | HIGH | MEDIUM | P1 |
| NSTextView with spell check | HIGH | MEDIUM | P1 |
| Grammar checking | MEDIUM | LOW | P1 (free with NSTextView) |
| Look Up in context menu | MEDIUM | LOW | P1 (free with NSTextView) |
| Quick Look in context menu | MEDIUM | LOW | P1 (reuses spacebar toggle) |
| Substitutions integration | LOW | LOW | P2 |
| Services submenu | LOW | HIGH | P3 |
| Move to Trash | LOW | MEDIUM | Omit |

---

## Competitor Feature Analysis

Context: No direct competitors for this exact use case, but adjacent tools inform user expectations.

| Feature | Finder | Xcode Project Navigator | VS Code File Explorer | Our Approach |
|---------|--------|------------------------|----------------------|--------------|
| Right-click context menu | Full native menu with Get Info, Open With, Share, etc. | Minimal: Show in Finder, Open with External Editor, New File | Open in Integrated Terminal, Reveal in Explorer, Copy Path | Focused: Reveal in Finder + Quick Look + Open in Finder for folders |
| Spacebar Quick Look | Yes, native | No (uses Quick Look via menu) | No | Yes, first-class via QLPreviewPanel |
| Spell check in text areas | N/A (no text editing) | Code-focused, no prose spell check | Extension-based | Yes, enabled by default via NSTextView |
| Grammar check | N/A | No | No | Yes, free with NSTextView |

---

## Sources

- [SwiftUI contextMenu(forSelectionType:menu:primaryAction:) — SerialCoder.dev](https://serialcoder.dev/text-tutorials/swiftui/enabling-selection-double-click-and-context-menus-in-swiftui-list-on-macos/)
- [Including Services in contextual menus in SwiftUI — Wade Tregaskis](https://wadetregaskis.com/including-services-in-contextual-menus-in-swiftui/)
- [Quick Look with NSTableView and Swift — DevGypsy](https://devgypsy.com/post/2023-06-06-quicklook-swift-tableview/)
- [Quick Look UI — Apple Developer Documentation](https://developer.apple.com/documentation/quicklookui)
- [quickLookPreview modifier — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/view/quicklookpreview(_:in:))
- [NSTextView — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nstextview)
- [NSTextView delegate menu:for:at: — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nstextviewdelegate/1449341-textview)
- [Spelling/grammar check settings — Apple Developer Forums](https://developer.apple.com/forums/thread/755777)
- [SwiftUI TextEditor spell check weirdness — Apple Developer Forums](https://developer.apple.com/forums/thread/744800)
- [Replace text and punctuation in documents on Mac — Apple Support](https://support.apple.com/guide/mac-help/replace-text-punctuation-documents-mac-mh35735/mac)
- [ContextMenu — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/contextmenu)

---
*Feature research for: LoRA Dataset Browser — v1.4 Native OS Integration*
*Researched: 2026-03-15*
