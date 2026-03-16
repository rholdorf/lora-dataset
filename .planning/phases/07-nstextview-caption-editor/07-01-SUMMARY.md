---
phase: 07-nstextview-caption-editor
plan: 01
subsystem: ui
tags: [nstextview, nsviewrepresentable, spell-check, grammar-check, appkit, macos]

# Dependency graph
requires: []
provides:
  - CaptionEditorView: NSViewRepresentable wrapping NSTextView with LoRA-safe settings
  - Unit tests verifying NSTextView property configuration (EDIT-01, 02, 04, 05)
  - ContentView updated to use CaptionEditorView instead of TextEditor
affects: [08-image-navigation, 09-quick-look]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - NSViewRepresentable wrapping NSScrollView containing NSTextView for scrollable plain-text editing
    - makeNSViewForTesting() helper method exposes NSView configuration for unit tests without needing NSViewRepresentable.Context
    - Dedicated UndoManager per text view instance, stored in coordinator, cleared on image switch via removeAllActions()
    - isUpdatingProgrammatically flag prevents textDidChange -> updateNSView feedback loops

key-files:
  created:
    - lora-dataset/lora-dataset/CaptionEditorView.swift
    - lora-dataset/lora-datasetTests/CaptionEditorViewTests.swift
  modified:
    - lora-dataset/lora-dataset/ContentView.swift

key-decisions:
  - "makeNSViewForTesting() static helper avoids needing NSViewRepresentable.Context in unit tests"
  - "substitutionsVerified flag in coordinator re-applies LoRA-safe settings once after first updateNSView to guard against macOS resetting properties"
  - "Monospace font (monospacedSystemFont size 13) used for caption editor — appropriate for LoRA training data"
  - "drawsBackground = false on both NSScrollView and NSTextView to blend with SwiftUI container"
  - "RoundedRectangle overlay border removed — NSScrollView provides clean appearance without extra border"

patterns-established:
  - "Pattern: makeNSViewForTesting() — expose NSView config logic for unit test access without Context"
  - "Pattern: substitutionsVerified guard — re-apply NSTextView settings once after first updateNSView"

requirements-completed: [EDIT-01, EDIT-02, EDIT-03, EDIT-04, EDIT-05]

# Metrics
duration: 4min
completed: 2026-03-16
---

# Phase 7 Plan 01: NSTextView Caption Editor Summary

**NSViewRepresentable CaptionEditorView wrapping NSTextView with spell check, grammar check, and all silent LoRA-corrupting substitutions disabled**

## Performance

- **Duration:** ~45 min (including human verification)
- **Started:** 2026-03-15T21:38:46Z
- **Completed:** 2026-03-16T00:42:00Z
- **Tasks:** 3 of 3 (all complete including human verification)
- **Files modified:** 4

## Accomplishments

- Created CaptionEditorView wrapping NSTextView with all LoRA-safe substitution settings
- Unit tests pass verifying EDIT-01 (spell check), EDIT-02 (grammar), EDIT-04 (no smart quotes/dashes), EDIT-05 (auto-language detection), and all silent substitutions disabled
- Replaced TextEditor in ContentView with CaptionEditorView; project builds clean, full test suite passes
- Per-image undo isolation using dedicated UndoManager per coordinator instance

## Task Commits

Each task was committed atomically:

1. **TDD RED - Failing tests for CaptionEditorView** - `b374302` (test)
2. **Task 1: CaptionEditorView implementation** - `2d87be6` (feat)
3. **Task 2: Replace TextEditor in ContentView** - `e07ab08` (feat)
4. **Fix: Spelling & Grammar menu** - `520cfcc` (fix) - Added TextEditingCommands to lora_datasetApp
5. **Fix: Grammar checking reliability** - `659ee54` (fix) - Used NSTextView subclass for reliable grammar checking
6. **Task 3: Human verification** - APPROVED by user (all EDIT-01 through EDIT-05 confirmed in running app)

## Files Created/Modified

- `lora-dataset/lora-dataset/CaptionEditorView.swift` - NSViewRepresentable wrapping NSTextView with all LoRA-safe settings, coordinator pattern, per-image undo isolation; uses NSTextView subclass for reliable grammar checking
- `lora-dataset/lora-datasetTests/CaptionEditorViewTests.swift` - Unit tests for NSTextView property configuration (7 tests, all passing)
- `lora-dataset/lora-dataset/ContentView.swift` - TextEditor replaced with CaptionEditorView in DetailView
- `lora-dataset/lora-dataset/lora_datasetApp.swift` - Added TextEditingCommands to expose Spelling & Grammar menu

## Decisions Made

- Used `makeNSViewForTesting()` helper to expose NSView configuration for unit tests without needing NSViewRepresentable.Context construction
- Added `substitutionsVerified` flag in coordinator to defensively re-apply LoRA-safe settings once after first `updateNSView` (guards against reported macOS resetting behavior)
- Used monospace font (size 13) as appropriate for LoRA training data captions
- Removed the RoundedRectangle overlay border from the original TextEditor — NSScrollView provides clean appearance without an extra stroke border

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed NSUndoManager renamed to UndoManager in Swift**
- **Found during:** Task 1 (CaptionEditorView implementation)
- **Issue:** `NSUndoManager` has been renamed to `UndoManager` in Swift (obsoleted in Swift 3); caused build error
- **Fix:** Changed `let textViewUndoManager = NSUndoManager()` to `let textViewUndoManager = UndoManager()`
- **Files modified:** lora-dataset/lora-dataset/CaptionEditorView.swift
- **Verification:** Build succeeded after fix, all tests passed
- **Committed in:** 2d87be6 (Task 1 commit)

---

**2. [Rule 1 - Bug] Spelling & Grammar menu not appearing in app menu bar**
- **Found during:** Task 3 (human verification)
- **Issue:** The Edit > Spelling and Grammar submenu was absent; `CaptionEditorView` NSTextView had the capabilities but no SwiftUI command group wired it up
- **Fix:** Added `.commands { TextEditingCommands() }` to the `WindowGroup` in `lora_datasetApp.swift`
- **Files modified:** lora-dataset/lora-dataset/lora_datasetApp.swift
- **Verification:** Menu appeared after change; human verified in running app
- **Committed in:** 520cfcc

**3. [Rule 1 - Bug] Grammar underlines not reliable with bare NSTextView**
- **Found during:** Task 3 (human verification)
- **Issue:** Grammar check green underlines were intermittently absent when using a plain NSTextView instance
- **Fix:** Introduced an NSTextView subclass (`CaptionNSTextView`) to improve reliability of grammar checking state
- **Files modified:** lora-dataset/lora-dataset/CaptionEditorView.swift
- **Verification:** Grammar underlines consistent in running app; human confirmed
- **Committed in:** 659ee54

---

**Total deviations:** 3 auto-fixed (1 blocking Swift API rename, 2 bugs found during human verification)
**Impact on plan:** All fixes required for correct behavior. No scope creep.

## Issues Encountered

- Xcode license agreement not accepted for `/Applications/Xcode.app` — switched to Xcode-beta.app which worked correctly. All builds and tests used Xcode 26.0 (beta).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CaptionEditorView ships spell check, grammar check, Look Up (built-in), no smart substitutions — all verified in running app
- All 5 EDIT requirements confirmed by human: EDIT-01 (spell underlines), EDIT-02 (grammar underlines), EDIT-03 (Look Up in context menu), EDIT-04 (no smart quotes/dashes), EDIT-05 (auto-language detection)
- Undo isolation confirmed: undo does not bleed across image switches
- Phase 7 Plan 01 complete — Phase 7 has no further plans; ready to proceed to Phase 8

---
*Phase: 07-nstextview-caption-editor*
*Completed: 2026-03-16*

## Self-Check: PASSED

- CaptionEditorView.swift: FOUND
- CaptionEditorViewTests.swift: FOUND
- lora_datasetApp.swift (TextEditingCommands): FOUND
- 07-01-SUMMARY.md: FOUND
- Commit b374302 (TDD RED): FOUND
- Commit 2d87be6 (feat implementation): FOUND
- Commit e07ab08 (ContentView update): FOUND
- Commit 520cfcc (TextEditingCommands fix): FOUND
- Commit 659ee54 (grammar subclass fix): FOUND
- Task 3: Human verification APPROVED
