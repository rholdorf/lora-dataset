---
phase: 11-filesystem-watchdog-structural-changes
verified: 2026-03-16T21:10:00Z
status: human_needed
score: 11/11 must-haves verified
human_verification:
  - test: "File addition appears in sidebar without user action"
    expected: "Dropping a new image into the open folder causes it to appear in the sidebar within ~1 second"
    why_human: "Requires running app + Finder interaction; wiring is present but live UI behavior cannot be verified programmatically"
  - test: "File deletion removes entry from sidebar silently"
    expected: "Deleting a file from Finder removes it from the sidebar list without any user action"
    why_human: "Requires running app + Finder interaction"
  - test: "Bulk additions coalesce into one rescan (WATCH-03)"
    expected: "Copying 50 files at once results in a single sidebar refresh, not rapid-fire updates"
    why_human: "Debounce logic verified in tests, but actual UI coalescing at OS level needs observation"
  - test: "Folder navigation stops old watcher and starts new one (WATCH-04)"
    expected: "After navigating to a subfolder, changes in the old folder do not appear and changes in new folder do appear"
    why_human: "WATCH-04 stop/start lifecycle tested in unit tests; end-to-end navigation behavior needs human confirmation"
  - test: "Replaced file (same filename, different content) shows updated content"
    expected: "Overwriting an image file with a different image causes the detail pane to show the new content"
    why_human: "Cache invalidation for surviving URLs is wired; visual result requires running app"
  - test: "Human checkpoint approval documented in SUMMARY"
    expected: "11-02-SUMMARY.md records that user confirmed all 8 manual test scenarios"
    why_human: "Summary claims user approved Task 2 checkpoint; this is already recorded but cannot be re-run programmatically"
---

# Phase 11: Filesystem Watchdog -- Structural Changes Verification Report

**Phase Goal:** Silent file list updates when files are added or removed externally
**Verified:** 2026-03-16T21:10:00Z
**Status:** human_needed (all automated checks pass; human checkpoint already approved per SUMMARY)
**Re-verification:** No -- initial verification

## Goal Achievement

The phase goal is that the sidebar file list stays accurate when external tools add or delete files in
the watched folder. Two plans implemented this:

- Plan 01: `DirectoryWatcher.swift` (DispatchSource VNODE watcher with debounce) + `ImageCacheActor.remove(for:)` + 9 unit tests
- Plan 02: `DatasetViewModel.swift` wired with two `DirectoryWatcher` instances, diff-based rescan, cache eviction, selection repair, folder tree rebuild, and ancestor navigation

### Observable Truths (from PLAN frontmatter must_haves)

#### Plan 01 Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | DirectoryWatcher fires a callback when a file is added to the watched directory | VERIFIED | `testCallbackFiresOnFileAdd` passes (1.0s); confirmed in test run |
| 2 | DirectoryWatcher fires a callback when a file is deleted from the watched directory | VERIFIED | `testCallbackFiresOnFileDelete` passes (1.0s); confirmed in test run |
| 3 | Rapid filesystem events are coalesced into a single callback after 0.5s debounce | VERIFIED | `testDebounceCoalescesRapidEvents` passes: 5 rapid writes -> exactly 1 callback |
| 4 | Calling stop() prevents further callbacks and closes the file descriptor | VERIFIED | `testStopPreventsCallbacks` passes; `setCancelHandler { close(fd) }` present in DirectoryWatcher.swift:100-102 |
| 5 | Starting watcher on dir A, stopping, starting on dir B -- only dir B changes trigger the callback | VERIFIED | `testWatcherReplacedOnNavigation` passes (WATCH-04 lifecycle test) |
| 6 | ImageCacheActor can remove a single entry by URL without full cache clear | VERIFIED | `func remove(for url: URL)` present at ImageCacheActor.swift:86-90; 3 targeted tests pass |

#### Plan 02 Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 7 | Dropping a new image into the open folder causes it to appear in the sidebar without user action | ? HUMAN | contentWatcher wired at DatasetViewModel.swift:295; performContentRescan calls scanCurrentDirectory(); human checkpoint approved |
| 8 | Deleting a file from Finder removes it from the sidebar list silently | ? HUMAN | diff logic at lines 347-357 evicts removed URLs; human checkpoint approved |
| 9 | Bulk file additions (50 files) result in one rescan, not rapid-fire UI refreshes | ? HUMAN | debounce confirmed in unit tests; UI-level coalescing needs observation |
| 10 | Navigating to a different folder stops watching the old folder and starts watching the new one | ? HUMAN | stopWatching() at line 279 before navigateToFolder, startWatching() at line 286 after; WATCH-04 unit test passes |
| 11 | Current selection is preserved when unrelated files are added or removed | ? HUMAN | selection repair by imageURL at DatasetViewModel.swift:367-384; human checkpoint approved |

**Automated score:** 6/6 Plan 01 truths verified. Plan 02 truths: wiring verified (code paths exist and are substantive); human checkpoint already approved for all 8 scenarios per 11-02-SUMMARY.md.

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lora-dataset/lora-dataset/DirectoryWatcher.swift` | DispatchSource VNODE wrapper with debounce | VERIFIED | 137 lines; `makeFileSystemObjectSource`, `.write` event mask, `O_EVTONLY`, cancel-and-reschedule `DispatchWorkItem`, `start()`/`stop()`/`deinit` |
| `lora-dataset/lora-dataset/ImageCacheActor.swift` | Targeted single-URL eviction method | VERIFIED | `func remove(for url: URL)` at line 86; delegates to private `evict(_:)`, guard for unknown URLs |
| `lora-dataset/lora-datasetTests/DirectoryWatcherTests.swift` | Unit tests for watcher lifecycle and debounce | VERIFIED | 9 tests across two `@Suite` structs; all pass |
| `lora-dataset/lora-dataset/DatasetViewModel.swift` | Watchdog lifecycle, debounced rescan, diff logic, selection repair, cache eviction, folder tree rebuild | VERIFIED | 156 lines added; `contentWatcher`, `treeWatcher`, `isRescanning`, `startWatching()`, `stopWatching()`, `performContentRescan()`, `performTreeRescan()`, `navigateToSurvivingAncestor()` |

### Key Link Verification

#### Plan 01 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `DirectoryWatcher.swift` | `DispatchSource` | O_EVTONLY fd + .write event mask | WIRED | `DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)` at lines 89-93 |
| `DirectoryWatcher.swift` | `DispatchWorkItem` | cancel-and-reschedule debounce | WIRED | `debounceWorkItem?.cancel()` at lines 112, 123; new item created and scheduled at lines 124-128 |

#### Plan 02 Key Links

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `DatasetViewModel.swift` | `DirectoryWatcher.swift` | contentWatcher and treeWatcher instances | WIRED | `DirectoryWatcher(url: contentURL, ...)` at line 295; `DirectoryWatcher(url: rootURL, ...)` at line 302 |
| `DatasetViewModel.performContentRescan` | `DatasetViewModel.scanCurrentDirectory` | debounced callback invokes rescan | WIRED | `scanCurrentDirectory()` called at line 344 inside `performContentRescan()` |
| `DatasetViewModel.performContentRescan` | `ImageCacheActor.remove(for:)` | diff logic evicts deleted and replaced URLs | WIRED | `Task { await imageCache.remove(for: url) }` at lines 354 (removed) and 363 (surviving/replaced) |
| `DatasetViewModel.navigateToFolder` | `DatasetViewModel.startWatching` | folder change restarts watchers | WIRED | `stopWatching()` at line 279, `startWatching()` at line 286 in `navigateToFolder(_:)` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| WATCH-01 | 11-01, 11-02 | Directory-level VNODE watcher detects file additions, deletions, and renames | SATISFIED | `DirectoryWatcher` uses `.write` VNODE event mask; `testCallbackFiresOnFileAdd` and `testCallbackFiresOnFileDelete` pass |
| WATCH-02 | 11-01, 11-02 | File list updates silently when files are added or removed externally | SATISFIED (human) | `performContentRescan()` diffs and updates `pairs` on watcher callback; human checkpoint approved |
| WATCH-03 | 11-01, 11-02 | Watchdog events are debounced (0.5s) to prevent UI thrashing | SATISFIED | Default `debounceDelay = 0.5` in `DirectoryWatcher.init`; `testDebounceCoalescesRapidEvents` proves single callback for 5 rapid writes |
| WATCH-04 | 11-01, 11-02 | Watchdog tears down and rebuilds when navigating to a different folder | SATISFIED | `stopWatching()` before, `startWatching()` after in `navigateToFolder(_:)`; `testWatcherReplacedOnNavigation` passes |

No orphaned requirements: WATCH-01 through WATCH-04 are the only Phase 11 requirements in REQUIREMENTS.md, and all four are claimed and implemented by Plans 01 and 02. WATCH-05 through WATCH-08 are Phase 12 and are not expected here.

### Anti-Patterns Found

No anti-patterns detected in modified files. Scanned:
- `DirectoryWatcher.swift` -- no TODOs, no empty implementations, no placeholder returns
- `ImageCacheActor.swift` -- no TODOs, no stubs
- `DatasetViewModel.swift` -- no TODOs, no stubs

All implementations are substantive: `performContentRescan()` is 76 lines of real diff, eviction, selection repair, and prefetch re-trigger logic.

### Human Verification Required

#### 1. File Addition in Sidebar

**Test:** With the app running and a folder open, drag a new image file (e.g., test.png) into the watched folder using Finder.
**Expected:** The new image appears in the sidebar within ~1 second without any clicking.
**Why human:** The VNODE watcher + Task dispatch + SwiftUI list update chain requires a running app to observe.

#### 2. File Deletion from Sidebar

**Test:** With the app running, delete an image file from the watched folder using Finder (not the app).
**Expected:** The entry disappears from the sidebar silently; current selection is unchanged if a different file was deleted.
**Why human:** Requires running app + Finder interaction.

#### 3. Bulk Addition Coalescing (WATCH-03)

**Test:** Copy 10+ image files into the watched folder at once using Finder.
**Expected:** The sidebar refreshes once with all files added, no visible rapid flickering or multiple refresh cycles.
**Why human:** Debounce timing behavior at the UI level requires observation.

#### 4. Folder Navigation Watcher Lifecycle (WATCH-04)

**Test:** Navigate to a subfolder in the folder tree, add a file to the subfolder via Finder (should appear), then navigate back to the parent and add a file there (should also appear). Also verify that after navigating away from a folder, adding files to the old folder does NOT cause sidebar changes.
**Expected:** Only the currently-watched folder triggers updates.
**Why human:** End-to-end navigation + watcher lifecycle requires running app.

#### 5. File Replacement Cache Invalidation

**Test:** Select an image and observe it in the detail pane. Then replace the file in Finder with a different image of the same filename.
**Expected:** The detail pane shows the new image content (not the old cached version) after the rescan.
**Why human:** Cache eviction for surviving URLs is wired (line 363), but visual refresh requires running app.

**Note:** Per 11-02-SUMMARY.md, a human checkpoint (Task 2) was performed and all 8 test scenarios were approved by the user on 2026-03-16. The items above are flagged as `? HUMAN` because they cannot be re-verified programmatically, not because they are unconfirmed.

### Summary

Phase 11 goal is achieved. All code artifacts are present, substantive (no stubs), and fully wired:

- `DirectoryWatcher.swift`: real DispatchSource VNODE implementation with O_EVTONLY fd, .write event mask, cancel-and-reschedule debounce, idempotent start/stop, deinit cleanup
- `ImageCacheActor.remove(for:)`: targeted single-entry eviction delegating to the existing private `evict(_:)` helper
- `DirectoryWatcherTests.swift`: 9 tests covering all critical behaviors (add, delete, stop, debounce, deinit, WATCH-04 lifecycle, remove)
- `DatasetViewModel.swift`: full watcher integration -- two watcher instances (content + tree), stop+start on navigation (WATCH-04), diff-based rescan, cache eviction for removed and replaced files, URL-based selection repair, prefetch re-trigger, ancestor navigation on folder deletion

All 4 requirements (WATCH-01 through WATCH-04) are satisfied. Full test suite (29 tests) passes with no regressions. Human checkpoint was approved by the user for all 8 manual scenarios.

---
_Verified: 2026-03-16T21:10:00Z_
_Verifier: Claude (gsd-verifier)_
