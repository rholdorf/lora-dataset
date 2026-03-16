---
phase: 07-nstextview-caption-editor
verified: 2026-03-15T22:30:00Z
status: human_needed
score: 6/7 must-haves verified
human_verification:
  - test: "Misspelled word shows red underline"
    expected: "Typing 'teh' in the caption editor produces a red underline beneath it"
    why_human: "NSTextView isContinuousSpellCheckingEnabled is set (confirmed by unit test), but actual underline rendering requires a live window context"
  - test: "Grammar issue shows green underline"
    expected: "Typing 'He go store' in the caption editor produces green underline beneath the grammatically incorrect phrase"
    why_human: "NSTextView isGrammarCheckingEnabled is set (confirmed by unit test and CaptionTextView subclass with viewDidMoveToWindow), but rendering requires a live window — SUMMARY records human approval for this item"
  - test: "Look Up appears in right-click context menu"
    expected: "Right-clicking any word shows a 'Look Up' item; clicking it opens the system Dictionary popup"
    why_human: "EDIT-03 is a built-in NSTextView capability requiring no code; cannot be verified programmatically"
  - test: "Smart quotes and smart dashes suppressed"
    expected: "Typing '\"' stays as a straight quote; typing '--' stays as two hyphens"
    why_human: "isAutomaticQuoteSubstitutionEnabled and isAutomaticDashSubstitutionEnabled are set false (unit test passes), but actual keystroke behaviour requires a live window"
  - test: "Auto-language detection adapts spell check"
    expected: "Typing a sentence in Portuguese or Spanish causes spell check to adapt without manual language selection"
    why_human: "NSSpellChecker.shared.automaticallyIdentifiesLanguages = true is confirmed by unit test; end-to-end language switching requires runtime observation"
  - test: "Undo isolation across image switches"
    expected: "Cmd+Z after switching images does NOT undo text from the previous image"
    why_human: "UndoManager per coordinator and removeAllActions() on image switch are present in code; isolation requires runtime verification across image selection changes"
---

# Phase 7: NSTextView Caption Editor Verification Report

**Phase Goal:** Replace SwiftUI TextEditor with NSTextView-based caption editor providing spell check, grammar check, dictionary Look Up, and LoRA-safe substitution settings
**Verified:** 2026-03-15T22:30:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Misspelled words in the caption editor show red underlines as the user types | ? HUMAN | `isContinuousSpellCheckingEnabled = true` in `makeNSViewForTesting()` and `CaptionTextView.viewDidMoveToWindow()`; unit test `testSpellCheckEnabled` passes; rendering needs live window |
| 2 | Grammar issues show green underlines in the caption editor | ? HUMAN | `isGrammarCheckingEnabled = true` in both `makeNSViewForTesting()` and `CaptionTextView.viewDidMoveToWindow()`; unit test `testGrammarCheckEnabled` passes; SUMMARY records human approval; rendering needs live window |
| 3 | User can right-click any word to see Look Up in the context menu | ? HUMAN | No code needed — built-in NSTextView capability; SUMMARY records human approval; cannot verify programmatically |
| 4 | Smart quotes and smart dashes do not activate when typing quotation marks or double-hyphens | ? HUMAN | `isAutomaticQuoteSubstitutionEnabled = false` and `isAutomaticDashSubstitutionEnabled = false` confirmed by unit test `testSmartSubstitutionsDisabled`; keystroke behaviour needs live window |
| 5 | Spell checking language switches automatically when typing in a different language | ? HUMAN | `NSSpellChecker.shared.automaticallyIdentifiesLanguages = true` confirmed by unit test `testAutoLanguageDetection`; language switching needs runtime observation |
| 6 | Undo history is cleared when switching between images | ? HUMAN | `context.coordinator.textViewUndoManager.removeAllActions()` called in `updateNSView` when `tv.string != text`; isolation requires runtime verification |
| 7 | Auto-correction, auto-capitalization, link detection, and text replacement are all disabled | VERIFIED | Unit test `testLoRASafeSettings` passes; all 4 properties explicitly set false in `makeNSViewForTesting()` and `CaptionTextView.viewDidMoveToWindow()` |

**Score:** 1/7 truths fully verified automatically; 6/7 require human confirmation (all are substantively implemented — the gap is runtime rendering, not missing code)

**Note:** The SUMMARY records human approval (Task 3: "APPROVED by user — all EDIT-01 through EDIT-05 confirmed in running app"). The items above flagged as HUMAN are coded correctly; the human gate was already completed during plan execution. This report flags them for completeness since programmatic verification of rendering is not possible.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lora-dataset/lora-dataset/CaptionEditorView.swift` | NSViewRepresentable wrapping NSTextView with LoRA-safe settings | VERIFIED | 178 lines; exports `CaptionEditorView` struct and `CaptionTextView` subclass; all required NSTextView properties set; coordinator with `textDidChange`, `undoManager(for:)`, and `isUpdatingProgrammatically` guard |
| `lora-dataset/lora-dataset/ContentView.swift` | Updated detail pane using CaptionEditorView instead of TextEditor | VERIFIED | Line 245: `CaptionEditorView(text: Binding(get:set:))` — TextEditor fully replaced; `.frame(minHeight: 200)` retained |
| `lora-dataset/lora-datasetTests/CaptionEditorViewTests.swift` | Unit tests for NSTextView property configuration | VERIFIED | 7 tests using Swift Testing (`@Test`, `#expect`); covers EDIT-01, EDIT-02, EDIT-04, EDIT-05, LoRA-safe settings, plain text, undo; `makeNSViewForTesting()` helper avoids NSViewRepresentable.Context construction |
| `lora-dataset/lora-dataset/lora_datasetApp.swift` | TextEditingCommands added to expose Spelling & Grammar menu | VERIFIED | Line 47: `TextEditingCommands()` present in `.commands` block — not in original PLAN but documented in SUMMARY as a bug fix during human verification |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `CaptionEditorView.swift` | `ContentView.swift` | `CaptionEditorView(text: Binding(…))` replacing TextEditor | WIRED | ContentView.swift line 245: exact pattern `CaptionEditorView(text: Binding(` present |
| `CaptionEditorView.Coordinator` | `NSTextView` | `func textDidChange` syncing text back to binding | WIRED | `CaptionEditorView.swift` line 123: `func textDidChange(_ notification: Notification)` with `parent.text = tv.string` |
| `CaptionEditorView.Coordinator` | `UndoManager` | `func undoManager(for:)` returning dedicated per-editor undo manager | WIRED | `CaptionEditorView.swift` line 131: `func undoManager(for view: NSTextView) -> UndoManager?` returning `textViewUndoManager` |

All 3 key links verified.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| EDIT-01 | 07-01-PLAN.md | Continuous spell checking — red underlines on unknown words | SATISFIED | `isContinuousSpellCheckingEnabled = true` in `CaptionTextView.viewDidMoveToWindow()` and `makeNSViewForTesting()`; unit test passes; human approved |
| EDIT-02 | 07-01-PLAN.md | Grammar checking — green underlines | SATISFIED | `isGrammarCheckingEnabled = true` in subclass and testing helper; unit test passes; human approved; NSTextView subclass used for reliability |
| EDIT-03 | 07-01-PLAN.md | Right-click "Look Up" dictionary definitions | SATISFIED | Built-in NSTextView capability; no code required; human confirmed present in context menu; `TextEditingCommands()` added to expose Spelling & Grammar menu |
| EDIT-04 | 07-01-PLAN.md | Smart quotes and smart dashes disabled by default | SATISFIED | `isAutomaticQuoteSubstitutionEnabled = false`, `isAutomaticDashSubstitutionEnabled = false` in both code paths; unit test `testSmartSubstitutionsDisabled` passes; human approved |
| EDIT-05 | 07-01-PLAN.md | Auto-language detection via NSSpellChecker | SATISFIED | `NSSpellChecker.shared.automaticallyIdentifiesLanguages = true` in both code paths; unit test `testAutoLanguageDetection` passes; human approved |

All 5 EDIT requirements claimed by 07-01-PLAN.md are accounted for and satisfied.

**Orphaned requirements check:** REQUIREMENTS.md maps EDIT-01 through EDIT-05 exclusively to Phase 7. No additional IDs mapped to Phase 7. No orphaned requirements.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| None found | - | - | - | - |

Scanned `CaptionEditorView.swift`, `ContentView.swift`, `CaptionEditorViewTests.swift`, and `lora_datasetApp.swift` for TODO/FIXME/placeholder/empty return patterns. None found.

### Test Results

All 7 unit tests in `CaptionEditorViewTests` pass in `** TEST SUCCEEDED **` runs. A transient flakiness was observed across multiple parallel runs: tests occasionally fail when run simultaneously because multiple test processes contend on the shared `NSSpellChecker.shared` singleton. Individual sequential runs always pass. This is a test isolation issue, not a production code defect.

**Flakiness severity:** Warning — tests pass when run in isolation; only fail when macOS parallelizes two test runner processes sharing `NSSpellChecker.shared.automaticallyIdentifiesLanguages`.

### Build Status

`xcodebuild build`: **BUILD SUCCEEDED** (clean, zero errors).

### Commit Verification

All 5 implementation commits from SUMMARY verified present in git history:
- `b374302` — test(07-01): TDD RED tests
- `2d87be6` — feat(07-01): CaptionEditorView implementation
- `e07ab08` — feat(07-01): replace TextEditor with CaptionEditorView
- `520cfcc` — fix(07): TextEditingCommands for Spelling & Grammar menu
- `659ee54` — fix(07): NSTextView subclass for reliable grammar checking

### Human Verification Required

The following items require a human to run the app and confirm. The SUMMARY records that Task 3 human verification was already completed and approved. These tests are documented here for completeness and reproducibility.

#### 1. Spell Check Underlines (EDIT-01)

**Test:** Open the app, select an image with a caption, type "teh" in the caption editor.
**Expected:** A red underline appears beneath "teh" as a misspelled word.
**Why human:** NSTextView renders underlines only within a live window context.

#### 2. Grammar Check Underlines (EDIT-02)

**Test:** Type "He go store" in the caption editor.
**Expected:** Green underlines appear beneath the grammatically incorrect construction.
**Why human:** Grammar underline rendering requires a live window; the NSTextView subclass (`CaptionTextView.viewDidMoveToWindow`) was introduced specifically to improve reliability here.

#### 3. Look Up in Context Menu (EDIT-03)

**Test:** Right-click any word in the caption editor.
**Expected:** "Look Up" appears in the context menu; clicking it opens the system Dictionary popup.
**Why human:** Built-in NSTextView capability; no code exists to verify.

#### 4. Smart Quotes and Dashes Suppressed (EDIT-04)

**Test:** Type `"` in the caption editor. Then type `--`.
**Expected:** Straight quote character `"` is produced (not `"` or `"`); two hyphens `--` remain as `--` (not `—`).
**Why human:** Substitution suppression is a keystroke-level behaviour that requires live input.

#### 5. Auto-Language Detection (EDIT-05)

**Test:** Type a sentence in Portuguese or Spanish.
**Expected:** Spell check underlines adapt to the detected language without any manual language selection.
**Why human:** NSSpellChecker language switching requires runtime text analysis.

#### 6. Undo Isolation Across Image Switches

**Test:** Edit caption for image A (type some text). Switch to image B. Press Cmd+Z.
**Expected:** Cmd+Z does NOT undo text from image A. The undo stack is fresh for image B.
**Why human:** UndoManager isolation requires exercising the image selection lifecycle.

### Gaps Summary

No code gaps found. All three artifacts exist, are substantive, and are fully wired. All 5 requirements are implemented. The phase goal is achieved at the code level.

The "human_needed" status reflects that 6 of 7 observable truths are rendering/runtime behaviours that cannot be verified by static analysis. The SUMMARY documents that a human completed Task 3 (human verification gate) and approved all items. If that approval is trusted as part of the phase record, the phase is complete.

---

_Verified: 2026-03-15T22:30:00Z_
_Verifier: Claude (gsd-verifier)_
