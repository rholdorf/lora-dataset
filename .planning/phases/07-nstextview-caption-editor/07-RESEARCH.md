# Phase 7: NSTextView Caption Editor - Research

**Researched:** 2026-03-15
**Domain:** AppKit NSTextView, NSViewRepresentable, NSSpellChecker
**Confidence:** HIGH

## Summary

Phase 7 replaces the SwiftUI `TextEditor` at `ContentView.swift:245-248` with a native `NSTextView` wrapper (`NSViewRepresentable`) that enables continuous spell checking, grammar checking, dictionary lookup, and disables all smart-substitution features that could silently corrupt LoRA training data tokens.

The core approach is well-established in the macOS AppKit ecosystem: wrap `NSTextView` (embedded in an `NSScrollView`) using the same `NSViewRepresentable` + coordinator pattern already used in `ZoomablePannableImage.swift`. The project's existing pattern handles the main architectural challenges (feedback loops, bidirectional state sync, `isUpdatingProgrammatically`). NSTextView exposes every required capability via explicit Bool properties — spell check, grammar check, and all substitution controls are simple property assignments, not custom code.

The undo manager strategy (per-image dedicated `NSUndoManager` stored in the coordinator, cleared on image switch via `removeAllActions()`) is the standard Cocoa pattern confirmed by Apple's `NSTextViewDelegate.undoManagerForTextView(_:)` delegate method.

**Primary recommendation:** Create a single `CaptionEditorView: NSViewRepresentable` struct that wraps `NSTextView.scrollableTextView()`, wires a coordinator as `NSTextViewDelegate`, sets all LoRA-safe substitution flags in `makeNSView`, and syncs text via `textDidChange` back to the binding.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **Auto-correction:** Disable auto-correction — spell check underlines errors but nothing gets auto-replaced
- **Auto-capitalization:** Disable auto-capitalization — LoRA prompts use specific casing conventions
- **Link detection:** Disable link detection — URLs stay as plain text, no clickable links
- **Text replacement:** Disable text replacement — no system substitutions (e.g., (c)→©), what you type is what gets saved
- **Smart quotes and smart dashes:** Disable (per EDIT-04) — protects LoRA training data tokens
- **Dirty indicator:** Tracks whether current text differs from last-saved text; undoing back to saved state clears dirty naturally
- **Undo history:** Preserved across saves (Cmd+Z can undo past save points, like TextEdit)
- **Undo on image switch:** History cleared on image switch — each image gets a fresh undo stack
- **No warning dialog on image switch:** Silent dirty state, user saves when ready

### Claude's Discretion
- Editor font, size, and line spacing
- Border and background styling (current TextEditor has a rounded rectangle stroke overlay)
- Internal padding/margins within the NSTextView
- How text changes sync back to the ViewModel binding

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| EDIT-01 | Caption text uses native NSTextView with continuous spell checking (red underlines on unknown words) | `isContinuousSpellCheckingEnabled = true` — direct property on NSTextView, macos(10.0+) |
| EDIT-02 | Caption text has grammar checking enabled (green underlines) | `isGrammarCheckingEnabled = true` (Swift name via `grammarCheckingEnabled` BOOL property, macos(10.5+)) |
| EDIT-03 | User can right-click for "Look Up" dictionary definitions on any word | Built-in to NSTextView's context menu — no custom code required; confirmed by SDK header delegate method `textView(_:menu:forEvent:atIndex:)` |
| EDIT-04 | Smart quotes and smart dashes are disabled by default to protect LoRA training data | `isAutomaticQuoteSubstitutionEnabled = false` + `isAutomaticDashSubstitutionEnabled = false` — direct instance properties confirmed in SDK header |
| EDIT-05 | Auto-language detection works natively via NSSpellChecker | `NSSpellChecker.shared.automaticallyIdentifiesLanguages = true` — confirmed in SDK header; default is typically already true; NSTextView delegates language identification to NSSpellChecker automatically |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| AppKit NSTextView | macOS 10.0+ | Native macOS text editor with full system services | Only way to get real spell check, grammar check, Look Up, and substitution control |
| NSScrollView | macOS 10.0+ | Scroll container for NSTextView | Required companion; NSTextView.scrollableTextView() is the idiomatic factory method |
| NSViewRepresentable | SwiftUI 1.0+ | Bridge NSTextView into SwiftUI | Same pattern as ZoomablePannableImage already in the project |
| NSUndoManager | Foundation | Per-image undo history | Standard Cocoa pattern; NSTextView manages its own undo actions via delegate |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| NSTextViewDelegate | macOS 10.0+ | Receive text changes, provide undo manager | Always required for binding sync |
| NSSpellChecker | macOS 10.5+ | Language identification confirmation | Only if confirming `automaticallyIdentifiesLanguages` at startup |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| NSTextView | SwiftUI TextEditor | TextEditor cannot disable smart quotes/dashes; confirmed broken spell check in some macOS versions |
| NSTextView | STTextView (third-party) | TextKit 2 based; adds dependency; not needed for plain-text caption editing |
| NSTextViewDelegate.textDidChange | NSTextStorage delegate | textStorage approach handles multi-byte emoji correctly but adds complexity; textDidChange is sufficient for plain-text captions |

**Installation:** No new dependencies — uses AppKit (already imported) and SwiftUI (already used).

## Architecture Patterns

### Recommended Project Structure
```
lora-dataset/
├── CaptionEditorView.swift    # New file: NSViewRepresentable wrapping NSTextView
└── ContentView.swift          # Existing: replace TextEditor with CaptionEditorView
```

A single new file is all that is required. No other files need structural changes — only `ContentView.swift:245-248` is replaced.

### Pattern 1: NSViewRepresentable with NSScrollView Container

**What:** Return `NSScrollView` (not `NSTextView`) from `makeNSView`/`updateNSView`. Extract the inner `NSTextView` via `scrollView.documentView as! NSTextView`.

**When to use:** Always for macOS text views that need scrolling. `NSTextView.scrollableTextView()` is the recommended factory (available macOS 10.14+).

**Example:**
```swift
// Source: AppKit SDK header — NSTextView.h (macOS 10.14+)
// + (NSScrollView *)scrollableTextView;
struct CaptionEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView

        // Delegate (text changes + undo manager)
        tv.delegate = context.coordinator

        // Plain text, no rich text formatting
        tv.isRichText = false

        // LoRA-safe: disable all silent substitutions
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false

        // Spell and grammar check (EDIT-01, EDIT-02)
        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = true

        // Undo (allowsUndo enables NSTextView's built-in undo)
        tv.allowsUndo = true

        // Layout: vertical resize, no horizontal scroll
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]

        // Font (Claude's discretion)
        tv.font = .systemFont(ofSize: NSFont.systemFontSize)

        // Initial text
        tv.string = text

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let tv = nsView.documentView as! NSTextView
        // Only update when change originated outside the text view
        guard !context.coordinator.isEditing else { return }
        if tv.string != text {
            context.coordinator.isUpdatingProgrammatically = true
            tv.string = text
            context.coordinator.isUpdatingProgrammatically = false
        }
    }
}
```

### Pattern 2: Coordinator as NSTextViewDelegate

**What:** Coordinator stores the `NSUndoManager`, implements `textDidChange` to sync back to the binding, and implements `undoManagerForTextView(_:)` to provide a per-image undo stack.

**When to use:** Always — required for bidirectional state sync and undo management.

**Example:**
```swift
// Source: AppKit SDK header — NSTextViewDelegate.h
extension CaptionEditorView {
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptionEditorView
        var isEditing = false
        var isUpdatingProgrammatically = false
        // Dedicated undo manager for this editor (not the window's)
        let textViewUndoManager = NSUndoManager()

        init(_ parent: CaptionEditorView) { self.parent = parent }

        // Sync text changes back to the SwiftUI binding
        func textDidChange(_ notification: Notification) {
            guard !isUpdatingProgrammatically,
                  let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        // Provide a dedicated undo manager so NSTextView's history is isolated
        func undoManager(for view: NSTextView) -> UndoManager? {
            return textViewUndoManager
        }
    }
}
```

### Pattern 3: Clearing Undo on Image Switch

**What:** When the selected image changes (`updateNSView` detects a text reset), call `textViewUndoManager.removeAllActions()` before updating the text view's content.

**When to use:** Whenever `updateNSView` updates `tv.string` with content from a new image (as opposed to a save sync for the current image).

**Example:**
```swift
// In updateNSView — called when vm.selectedID changes and ContentView pushes new captionText
func updateNSView(_ nsView: NSScrollView, context: Context) {
    let tv = nsView.documentView as! NSTextView
    guard !context.coordinator.isEditing else { return }
    if tv.string != text {
        context.coordinator.isUpdatingProgrammatically = true
        // Clear undo history for the new image
        context.coordinator.textViewUndoManager.removeAllActions()
        tv.string = text
        context.coordinator.isUpdatingProgrammatically = false
    }
}
```

**Caveat:** This clears undo on ANY external text update (save sync too). To avoid clearing after save, the caller can track whether the update is an image switch vs. a reload. The simplest approach is to always clear — since after save the current text == savedText, the user has nothing to undo. After reload (which resets to savedCaptionText) clearing is also correct.

### Anti-Patterns to Avoid

- **Setting `tv.string` inside `textDidChange`:** Causes infinite feedback loop. Guard with `isUpdatingProgrammatically`.
- **Returning a new `NSUndoManager()` from `undoManagerForTextView(_:)` on every call:** Creates a fresh manager each delegation call, destroying undo history. Store one instance in the coordinator.
- **Forgetting `isRichText = false`:** NSTextView defaults to rich text. Without this, pasting styled text introduces NSAttributedString formatting that `tv.string` strips but `textStorage` sees differently.
- **Configuring substitutions on `NSSpellChecker.shared`:** Substitution properties must be set on the `NSTextView` instance, not on the shared spell checker. Per-view properties are instance-level.
- **Hosting just `NSTextView` (not `NSScrollView`) as the NSViewRepresentable return type:** NSTextView doesn't scroll on its own; must be embedded in NSScrollView.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Spell check red underlines | Custom underline drawing | `isContinuousSpellCheckingEnabled = true` | NSTextView invokes NSSpellChecker automatically on every keystroke |
| Grammar check green underlines | Custom grammar engine | `isGrammarCheckingEnabled = true` | NSTextView calls NSSpellChecker.checkGrammarOfString internally; same TextEdit behavior |
| "Look Up" context menu item | Custom NSMenu entry | Nothing — it's built in | NSTextView's default `menuForEvent:` includes "Look Up" for any selected word when system dictionary is available |
| Auto-language detection | Language detection logic | `NSSpellChecker.shared.automaticallyIdentifiesLanguages = true` | NSSpellChecker identifies language via NSOrthography; NSTextView triggers this during continuous checking |
| Undo/redo | NSUndoManager registration | `allowsUndo = true` + dedicated NSUndoManager | NSTextView registers all text edits with the provided undo manager automatically |
| Smart quotes/dashes disable | String post-processing | `isAutomaticQuoteSubstitutionEnabled = false` + `isAutomaticDashSubstitutionEnabled = false` | Property set once in makeNSView; no character interception needed |

**Key insight:** Every feature in this phase is a property assignment on NSTextView. The complexity is in the SwiftUI integration plumbing (coordinator, feedback loop prevention, undo lifecycle) — not in the feature capabilities themselves.

## Common Pitfalls

### Pitfall 1: Feedback Loop in updateNSView
**What goes wrong:** Setting `tv.string = text` in `updateNSView` triggers `textDidChange`, which updates the binding, which calls `updateNSView` again — infinite loop.
**Why it happens:** `textDidChange` fires on any programmatic string assignment, not just user edits.
**How to avoid:** Guard with `isUpdatingProgrammatically` flag in the coordinator (same pattern as `ZoomablePannableImage.isUpdatingProgrammatically`).
**Warning signs:** CPU spike, app freeze, or rapid view redraws after first keystroke.

### Pitfall 2: Undo History Leaking Across Images
**What goes wrong:** Cmd+Z in image B undoes text from image A.
**Why it happens:** NSTextView's default undo manager is the window's `NSUndoManager`, which persists across all interactions.
**How to avoid:** Implement `undoManagerForTextView(_:)` in the coordinator, returning a dedicated `NSUndoManager` stored as a coordinator property. Call `removeAllActions()` on it in `updateNSView` when the text is reset for a new image.
**Warning signs:** Undo crosses image boundaries or keeps history after selecting a new sidebar item.

### Pitfall 3: Substitution Properties Reset by System
**What goes wrong:** Smart quotes re-enable themselves after the view is shown.
**Why it happens:** NSTextView can read substitution defaults from `NSUserDefaults` on certain system versions, overriding what was set in `makeNSView`. There are historical reports (pre-macOS 13) of `isContinuousSpellCheckingEnabled` being reverted to `false` by SwiftUI update cycles.
**How to avoid:** Re-apply substitution settings in `updateNSView` as well as `makeNSView`, but guard to only set them once (check current value before setting). Alternatively, override in a custom NSTextView subclass.
**Warning signs:** Smart quotes appear in output file despite setting the property; spell check stops working after first `updateNSView` call.

### Pitfall 4: isRichText Default
**What goes wrong:** Pasted styled text appears unstyled in the view but stores attributes in NSTextStorage; `tv.string` appears correct but the attributed content is wrong.
**Why it happens:** `isRichText` defaults to `true` for NSTextView.
**How to avoid:** Set `tv.isRichText = false` in `makeNSView`.
**Warning signs:** Paste operations change font or color; copy/paste produces RTF-wrapped text.

### Pitfall 5: NSScrollView Background Showing Through
**What goes wrong:** The NSScrollView shows a white/grey background that doesn't match the SwiftUI view background.
**Why it happens:** NSScrollView has `drawsBackground = true` by default.
**How to avoid:** Set `scrollView.drawsBackground = false` and optionally `tv.drawsBackground = false` if transparent background is desired.
**Warning signs:** Visible background color mismatch in dark mode.

### Pitfall 6: "Look Up" Not Appearing in Context Menu
**What goes wrong:** Right-click on a word in the editor doesn't show "Look Up [word]".
**Why it happens:** "Look Up" requires the user to have a word selected (or cursor positioned in a word) AND the system dictionary service to be available. It is present by default in NSTextView's `menuForEvent:` output.
**How to avoid:** No action required — it's built in. Verify with a right-click in the live app.
**Warning signs:** "Look Up" missing — check that `isEditable = true` (default) and no delegate override of `textView(_:menu:forEvent:atIndex:)` is removing it.

## Code Examples

### Complete CaptionEditorView skeleton
```swift
// Source: SDK headers — NSTextView.h, NSTextViewDelegate.h (macOS 10.14+)
import SwiftUI
import AppKit

struct CaptionEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView

        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true

        // EDIT-01: continuous spell check (red underlines)
        tv.isContinuousSpellCheckingEnabled = true
        // EDIT-02: grammar check (green underlines)
        tv.isGrammarCheckingEnabled = true

        // Locked decisions: LoRA-safe substitution settings
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false

        // Layout
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.font = .systemFont(ofSize: NSFont.systemFontSize)
        scrollView.drawsBackground = false

        tv.string = text
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let tv = nsView.documentView as! NSTextView
        guard !context.coordinator.isUpdatingProgrammatically else { return }
        if tv.string != text {
            context.coordinator.isUpdatingProgrammatically = true
            context.coordinator.textViewUndoManager.removeAllActions()
            tv.string = text
            context.coordinator.isUpdatingProgrammatically = false
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptionEditorView
        var isUpdatingProgrammatically = false
        let textViewUndoManager = NSUndoManager()

        init(_ parent: CaptionEditorView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isUpdatingProgrammatically,
                  let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        func undoManager(for view: NSTextView) -> UndoManager? {
            textViewUndoManager
        }
    }
}
```

### Replacing TextEditor in ContentView
```swift
// Current (ContentView.swift:245-248):
TextEditor(text: Binding(
    get: { vm.pairs[idx].captionText },
    set: { vm.pairs[idx].captionText = $0 }
))

// Replacement:
CaptionEditorView(text: Binding(
    get: { vm.pairs[idx].captionText },
    set: { vm.pairs[idx].captionText = $0 }
))
```

The `.font(.body)` modifier and `.overlay(RoundedRectangle...)` from the TextEditor block (lines 249-253) will need adjustments — font is configured inside `makeNSView`, and the border overlay `.overlay(RoundedRectangle(cornerRadius: 4).stroke(...))` can remain on the SwiftUI wrapper or be replaced with a custom NSView border (Claude's discretion).

### EDIT-05: Confirming auto-language detection
```swift
// Source: AppKit SDK header — NSSpellChecker.h (macOS 10.6+)
// Verify this is true at app start (it is the system default):
// NSSpellChecker.shared.automaticallyIdentifiesLanguages = true
// No action needed — NSTextView delegates to NSSpellChecker automatically.
// NSSpellChecker identifies language via NSOrthography during checkGrammarOfString/checkSpellingOfString.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual NSTextView + NSScrollView setup | `NSTextView.scrollableTextView()` factory | macOS 10.14 | Reduces boilerplate; returns pre-configured NSScrollView with NSTextView |
| TextKit 1 (NSLayoutManager) | TextKit 2 (NSTextLayoutManager) | macOS 12 / iOS 16 | For new code targeting macOS 12+, TextKit 2 is the default; `scrollableTextView()` uses TextKit 2 on macOS 12+ |
| SwiftUI TextEditor for macOS | NSTextView via NSViewRepresentable | Ongoing | TextEditor wraps NSTextView but exposes no substitution controls |

**Deprecated/outdated:**
- `NSTextView.scrollableDocumentContentTextView()`: Returns a content-area-specific variant; prefer `scrollableTextView()` for general editing.

## Open Questions

1. **Substitution properties being reverted by SwiftUI update cycles**
   - What we know: Historical reports on macOS Ventura and earlier of `isContinuousSpellCheckingEnabled` reverting after `updateNSView`. The fix is to re-apply in `updateNSView` or subclass.
   - What's unclear: Whether this affects macOS Sequoia (macOS 15).
   - Recommendation: Re-apply substitution settings in `updateNSView` guarded by a `firstSetupDone` flag on the coordinator. Set properties only once after first `makeNSView`.

2. **`isUpdatingProgrammatically` guard is sufficient for `textDidChange` but not for `textViewDidChangeSelection`**
   - What we know: This phase does not require selection tracking.
   - What's unclear: Whether selection changes during programmatic `tv.string = text` will cause any side effects.
   - Recommendation: Not a concern for this phase; `textDidChange` is the only delegate method needed.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (Xcode built-in) |
| Config file | lora-dataset/lora-dataset.xcodeproj (scheme: lora-dataset) |
| Quick run command | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset 2>&1 | tail -20` |
| Full suite command | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EDIT-01 | NSTextView has `isContinuousSpellCheckingEnabled = true` after makeNSView | unit | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests/CaptionEditorViewTests/testSpellCheckEnabled` | ❌ Wave 0 |
| EDIT-02 | NSTextView has `isGrammarCheckingEnabled = true` after makeNSView | unit | `xcodebuild test ... -only-testing:lora-datasetTests/CaptionEditorViewTests/testGrammarCheckEnabled` | ❌ Wave 0 |
| EDIT-03 | "Look Up" menu item present in NSTextView context menu | manual-only | N/A — NSMenu population requires UI interaction | manual |
| EDIT-04 | `isAutomaticQuoteSubstitutionEnabled = false` and `isAutomaticDashSubstitutionEnabled = false` after makeNSView | unit | `xcodebuild test ... -only-testing:lora-datasetTests/CaptionEditorViewTests/testSmartSubstitutionsDisabled` | ❌ Wave 0 |
| EDIT-05 | `NSSpellChecker.shared.automaticallyIdentifiesLanguages == true` | unit | `xcodebuild test ... -only-testing:lora-datasetTests/CaptionEditorViewTests/testAutoLanguageDetection` | ❌ Wave 0 |

**Note on EDIT-03:** "Look Up" is a system-provided context menu item in NSTextView's `menuForEvent:`. Testing it requires UI automation (XCUITest) or manual verification. Manual verification in the running app is sufficient for this phase.

### Sampling Rate
- **Per task commit:** Build the app and verify the caption editor appears and accepts text.
- **Per wave merge:** `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `lora-dataset/lora-datasetTests/CaptionEditorViewTests.swift` — covers EDIT-01, EDIT-02, EDIT-04, EDIT-05 (NSTextView property assertions after constructing a `CaptionEditorView`)

## Sources

### Primary (HIGH confidence)
- AppKit SDK header `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSTextView.h` — all NSTextView Bool properties for spell check, grammar, substitutions, undo, rich text
- AppKit SDK header `NSTextViewDelegate.h` — `undoManagerForTextView(_:)`, `textDidChange(_:)` delegate methods
- AppKit SDK header `NSSpellChecker.h` — `automaticallyIdentifiesLanguages` property with inline documentation
- AppKit SDK header `NSText.h` — `textDidChange`, `textDidBeginEditing` NSTextDelegate methods

### Secondary (MEDIUM confidence)
- [Blue Lemon Bits: Using NSTextView in SwiftUI](https://bluelemonbits.com/2021/11/14/using-nstextview-in-swiftui/) — `NSTextView.scrollableTextView()` pattern, coordinator `textDidChange` implementation
- [Oliver Epper: Wrap NSTextView in SwiftUI](https://oliver-epper.de/posts/wrap-nstextview-in-swiftui/) — `isUpdatingProgrammatically` / `shouldUpdateText` feedback prevention pattern
- [Prevent NSTextView from polluting undo history](https://www.markusbodner.com/til/2021/04/30/prevent-nstextview-from-polluting-undo-history/) — dedicated `NSUndoManager` per text view + `removeAllActions()` pattern
- [Swift Forums: How does NSTextView invoke grammar checking internally](https://forums.swift.org/t/how-does-nstextview-invoke-grammar-checking-internally/84832) — grammar checking via NSSpellChecker internals

### Tertiary (LOW confidence)
- [Apple Developer Forums: SwiftUI TextEditor spell check weirdness](https://developer.apple.com/forums/thread/744800) — reports of isContinuousSpellCheckingEnabled reverting on some macOS versions; recommend defensive re-apply in updateNSView

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all properties verified in SDK headers
- Architecture: HIGH — NSViewRepresentable + coordinator is the established project pattern; ZoomablePannableImage.swift is the direct analogue
- Pitfalls: HIGH (feedback loop, undo isolation) / MEDIUM (substitution revert on older macOS)

**Research date:** 2026-03-15
**Valid until:** 2026-09-15 (stable AppKit APIs; 6-month validity)
