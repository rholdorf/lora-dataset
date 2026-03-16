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

- **Duration:** 4 min
- **Started:** 2026-03-16T00:37:55Z
- **Completed:** 2026-03-16T00:41:53Z
- **Tasks:** 2 of 3 (Task 3 awaiting human verification)
- **Files modified:** 3

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

_Note: Task 3 is a human-verify checkpoint — awaiting user confirmation_

## Files Created/Modified

- `lora-dataset/lora-dataset/CaptionEditorView.swift` - NSViewRepresentable wrapping NSTextView with all LoRA-safe settings, coordinator pattern, per-image undo isolation
- `lora-dataset/lora-datasetTests/CaptionEditorViewTests.swift` - Unit tests for NSTextView property configuration (7 tests, all passing)
- `lora-dataset/lora-dataset/ContentView.swift` - TextEditor replaced with CaptionEditorView in DetailView

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

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary Swift API name correction. No scope creep.

## Issues Encountered

- Xcode license agreement not accepted for `/Applications/Xcode.app` — switched to Xcode-beta.app which worked correctly. All builds and tests used Xcode 26.0 (beta).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- CaptionEditorView ships spell check, grammar check, Look Up (built-in), no smart substitutions
- Task 3 (human-verify checkpoint) must be completed before plan is considered fully done
- After user verifies the running app, this plan is complete and Phase 7 can continue

---
*Phase: 07-nstextview-caption-editor*
*Completed: 2026-03-16*

## Self-Check: PASSED

- CaptionEditorView.swift: FOUND
- CaptionEditorViewTests.swift: FOUND
- 07-01-SUMMARY.md: FOUND
- Commit b374302 (TDD RED): FOUND
- Commit 2d87be6 (feat implementation): FOUND
- Commit e07ab08 (ContentView update): FOUND
