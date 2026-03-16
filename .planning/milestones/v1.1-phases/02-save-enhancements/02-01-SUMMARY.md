# Phase 02-01: Save Enhancements Summary

**Cmd+S keyboard shortcut with File menu integration and orange dirty indicator in sidebar**

## Performance

- **Duration:** 11 min
- **Started:** 2025-12-21T11:49:31Z
- **Completed:** 2025-12-21T12:00:47Z
- **Tasks:** 4 (3 auto + 1 checkpoint)
- **Files modified:** 4

## Accomplishments

- Dirty state tracking via `isDirty` computed property comparing `captionText` vs `savedCaptionText`
- File → Save menu item with Cmd+S shortcut, properly enabled/disabled based on dirty state
- Orange dot indicator in sidebar next to files with unsaved changes
- Save operation updates `savedCaptionText` to clear dirty state

## Files Created/Modified

- `lora-dataset/lora-dataset/ImageCaptionPair.swift` - Added `savedCaptionText` property and `isDirty` computed property; fixed Equatable to include text fields
- `lora-dataset/lora-dataset/DatasetViewModel.swift` - Added `selectedIsDirty` computed property; updated save/reload to sync `savedCaptionText`
- `lora-dataset/lora-dataset/lora_datasetApp.swift` - Added FocusedValueKey infrastructure and File → Save menu command with Cmd+S
- `lora-dataset/lora-dataset/ContentView.swift` - Added `.focusedValue` modifier and orange dot indicator; fixed folder click with Button

## Decisions Made

- Used separate `SaveButtonView` with `@ObservedObject` to properly observe ViewModel changes in menu commands (FocusedValue alone doesn't observe internal state changes)
- Included `captionText` and `savedCaptionText` in Equatable to ensure SwiftUI detects changes for dirty indicator updates
- Used Button with `.buttonStyle(.plain)` for folder rows instead of `onTapGesture` to fix first-click navigation issue

## Deviations from Plan

### Bug Fixes During Verification

**1. [Rule 1 - Bug] Fixed folder first-click not navigating**
- **Found during:** Checkpoint verification
- **Issue:** `onTapGesture` in OutlineGroup conflicted with List selection; first click selected row, second click triggered gesture
- **Fix:** Replaced `onTapGesture` with `Button` using `.buttonStyle(.plain)`
- **Files modified:** ContentView.swift

**2. [Rule 1 - Bug] Fixed dirty indicator not appearing**
- **Found during:** Checkpoint verification
- **Issue:** Custom Equatable only compared `id`, so SwiftUI didn't detect `captionText` changes
- **Fix:** Added `captionText` and `savedCaptionText` to Equatable comparison
- **Files modified:** ImageCaptionPair.swift

**3. [Rule 1 - Bug] Fixed Cmd+S always disabled**
- **Found during:** Checkpoint verification
- **Issue:** `@FocusedValue` doesn't observe ViewModel's @Published changes
- **Fix:** Created child `SaveButtonView` with `@ObservedObject` to properly observe ViewModel
- **Files modified:** lora_datasetApp.swift

---

**Total deviations:** 3 auto-fixed bugs
**Impact on plan:** All fixes necessary for correct operation. No scope creep.

## Issues Encountered

None beyond the bugs fixed above.

## Next Phase Readiness

Phase 2 complete. Save enhancements working:
- Cmd+S saves current caption
- File → Save menu works with proper enable/disable state
- Orange dot shows unsaved changes
- All save workflows functional

Ready for Phase 3: Security & Persistence

---
*Phase: 02-save-enhancements*
*Completed: 2025-12-21*
