---
phase: 10-image-cache-prefetch
plan: 02
subsystem: cache
tags: [swift, actor, ImageCacheActor, prefetch, LRU, spinner, CGImageSource, SwiftUI]

# Dependency graph
requires:
  - phase: 10-01
    provides: "ImageCacheActor actor and loadImage(url:maxPixelSize:) free function"
provides:
  - "Cache-first image loading in ContentView via ImageCacheActor.image(for:)"
  - "triggerPrefetch(aroundID:) on DatasetViewModel: +/-2 neighbor enqueue + stale task cancellation"
  - "150ms-delayed spinner overlay on dimmed previous image during cache miss"
  - "Error state: warning icon + filename for load failures"
  - "Cache and prefetch cleared on folder navigation (navigateToFolder + chooseDirectory)"
  - "Initial prefetch on folder load (scanCurrentDirectory)"
  - "DatasetViewModelCacheTests: CACHE-03 and CACHE-06 unit tests"
affects: [11-live-sync, 12-dirty-conflict]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Cache-first async image loading: actor await before Task.detached decode"
    - "Stale-guard pattern: selectedFileID == capturedID prevents wrong-image flash on rapid navigation"
    - "150ms-delayed spinner: inner Task.sleep with cancel on fast loads avoids spinner flash"
    - "Cost calculation from NSImage.representations.first?.pixelsWide * pixelsHigh * 4"

key-files:
  created:
    - lora-dataset/lora-datasetTests/DatasetViewModelCacheTests.swift
  modified:
    - lora-dataset/lora-dataset/DatasetViewModel.swift
    - lora-dataset/lora-dataset/ContentView.swift

key-decisions:
  - "prefetchTasks is private(set) not private so unit tests can inspect the dictionary directly"
  - "loadImageForSelection uses Task { @MainActor in } (not Task.detached) so it can call vm.imageCache and vm.triggerPrefetch from main actor"
  - "Spinner overlays previous image rather than replacing it — preserves visual context during slow loads"
  - "Error state uses exclamationmark.triangle + filename text instead of red error string"

patterns-established:
  - "Cache integration pattern: await actor method on main actor before spawning detached decode"
  - "[cache] print prefix for debug logging follows [saveSelected] convention"

requirements-completed: [CACHE-01, CACHE-03, CACHE-06]

# Metrics
duration: 5min
completed: 2026-03-16
---

# Phase 10 Plan 02: Cache Wiring Summary

**ImageCacheActor + CGImageSource wired into DatasetViewModel (prefetch, stale cancellation) and ContentView (cache-first load, 150ms spinner overlay, load-error state)**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-16T19:30:01Z
- **Completed:** 2026-03-16T19:35:56Z
- **Tasks:** 3 complete (Task 4 is checkpoint:human-verify, awaiting user)
- **Files modified:** 3 (2 modified, 1 created)

## Accomplishments
- `DatasetViewModel` gains `imageCache` (ImageCacheActor) and `triggerPrefetch(aroundID:displaySize:)` which enqueues +/-2 neighbor tasks and cancels stale ones outside the new window
- `ContentView.loadImageForSelection()` now checks cache first (O(1) hit), falls back to CGImageSource decode at 800px on miss, inserts into cache, then triggers prefetch
- 150ms-delayed `ProgressView` overlay on dimmed previous image for cache misses; load failure shows warning icon + filename
- `DatasetViewModelCacheTests` covers CACHE-03 (neighbor enqueue) and CACHE-06 (stale cancellation) — both pass
- 20 total tests passing (12 unit + 6 UI + 2 cache)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add prefetch management and cache instance to DatasetViewModel** - `084aa2c` (feat)
2. **Task 2: Add DatasetViewModelCacheTests for prefetch enqueue and stale cancellation** - `fa9f4d2` (test)
3. **Task 3: Wire cache-first loading, spinner overlay, and error state into ContentView** - `5d0b663` (feat)

**Plan metadata:** _(pending final docs commit)_

## Files Created/Modified
- `lora-dataset/lora-dataset/DatasetViewModel.swift` - Added imageCache, prefetchTasks, triggerPrefetch(), cache clear in navigateToFolder/chooseDirectory, initial prefetch in scanCurrentDirectory
- `lora-dataset/lora-dataset/ContentView.swift` - Cache-first loadImageForSelection, spinner state, error state, updated DetailView bindings
- `lora-dataset/lora-datasetTests/DatasetViewModelCacheTests.swift` - Two tests: testPrefetchEnqueuedForNeighbors (CACHE-03) and testStalePrefetchCancelled (CACHE-06)

## Decisions Made
- `prefetchTasks` is `private(set)` rather than `private` so unit tests can inspect the task dictionary without needing a separate accessor
- `loadImageForSelection` runs as `Task { @MainActor in }` (not `Task.detached`) so it can access actor-isolated vm properties and call vm methods directly
- Spinner overlays the previous image rather than clearing it first — user sees the last image dimmed with a spinner, which is less jarring than a blank frame

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Full image cache + prefetch system is complete and tested
- Task 4 (checkpoint:human-verify) requires the user to run the app and confirm behavior: cache hit speed, prefetch, spinner, rapid navigation, folder change cache clear, error state
- Phase 11 (live sync) can use the established [cache] print prefix convention for its own debug logging
- Phase 11 blocker: empirically validate DispatchSource VNODE .write event fires on file add/delete before building dependent logic (noted in STATE.md)

## Self-Check: PASSED

- FOUND: lora-dataset/lora-dataset/DatasetViewModel.swift
- FOUND: lora-dataset/lora-dataset/ContentView.swift
- FOUND: lora-dataset/lora-datasetTests/DatasetViewModelCacheTests.swift
- FOUND: .planning/phases/10-image-cache-prefetch/10-02-SUMMARY.md
- FOUND: commit 084aa2c (Task 1)
- FOUND: commit fa9f4d2 (Task 2)
- FOUND: commit 5d0b663 (Task 3)

---
*Phase: 10-image-cache-prefetch*
*Completed: 2026-03-16*
