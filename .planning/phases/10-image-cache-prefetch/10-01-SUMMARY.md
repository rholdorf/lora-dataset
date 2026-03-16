---
phase: 10-image-cache-prefetch
plan: 01
subsystem: cache
tags: [swift, actor, CGImageSource, LRU, memory-pressure, ImageIO, NSImage]

# Dependency graph
requires: []
provides:
  - "loadImage(url:maxPixelSize:) free function decoding images via CGImageSourceCreateThumbnailAtIndex at display size"
  - "ImageCacheActor: Swift actor with O(1) LRU lookup, width*height*4 cost accounting, 15% physicalMemory budget"
  - "Memory pressure monitoring: DispatchSource.makeMemoryPressureSource with .warning→50% eviction, .critical→full clear"
  - "10 unit tests covering cache hit/miss, cost, LRU order, evictToFraction, clear, and memory pressure events"
affects: [10-02-prefetch-wiring]

# Tech tracking
tech-stack:
  added: [ImageIO framework (CGImageSource)]
  patterns: [Swift actor for thread-safe shared cache, DispatchSource memory pressure monitor, accessOrder array for LRU tracking]

key-files:
  created:
    - lora-dataset/lora-dataset/ImageLoader.swift
    - lora-dataset/lora-dataset/ImageCacheActor.swift
    - lora-dataset/lora-datasetTests/ImageLoaderTests.swift
    - lora-dataset/lora-datasetTests/ImageCacheActorTests.swift
  modified: []

key-decisions:
  - "Used [URL] access-order array (front=MRU) alongside dictionary for simpler LRU implementation — acceptable for dataset sizes in the hundreds"
  - "budgetBytes initializer accepts optional override for testing; production default is 15% of ProcessInfo.processInfo.physicalMemory"
  - "NSImage Sendable conformance via extension NSImage: @unchecked @retroactive Sendable at file scope"
  - "Test PNG file written to FileManager.default.temporaryDirectory (not /tmp) to satisfy macOS sandbox restrictions"

patterns-established:
  - "ImageCacheActor: expose currentTotalCost and entryCount for test assertions without breaking actor isolation"
  - "handleMemoryPressure(_:) as a non-private actor method so tests can call it directly without going through DispatchSource"
  - "[cache] print prefix for debug logging follows existing [saveSelected] convention"

requirements-completed: [CACHE-01, CACHE-02, CACHE-04, CACHE-05]

# Metrics
duration: 5min
completed: 2026-03-16
---

# Phase 10 Plan 01: Image Cache Core Summary

**CGImageSource thumbnail decoder (ImageLoader) and LRU actor cache (ImageCacheActor) with adaptive 15%-RAM budget and DispatchSource memory pressure eviction**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-16T19:21:20Z
- **Completed:** 2026-03-16T19:26:04Z
- **Tasks:** 1 (TDD: RED → GREEN)
- **Files modified:** 4 created

## Accomplishments
- `loadImage(url:maxPixelSize:)` decodes images at display size via CGImageSource, forcing immediate pixel decode and respecting EXIF orientation — avoids loading full-resolution data into memory
- `ImageCacheActor` provides O(1) NSImage lookup with LRU eviction, width×height×4 cost accounting, and an adaptive budget (15% of physical RAM)
- Memory pressure monitoring via `DispatchSource.makeMemoryPressureSource`: warning events trim cache to 50% of budget, critical events clear everything
- 10 new unit tests all passing alongside 8 existing tests (18 total green)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ImageLoader.swift and ImageCacheActor.swift** - `e5325a6` (feat)

**Plan metadata:** _(pending final docs commit)_

_Note: TDD task — RED phase confirmed build failure, GREEN phase all 18 tests pass_

## Files Created/Modified
- `lora-dataset/lora-dataset/ImageLoader.swift` - Free function `loadImage(url:maxPixelSize:)` using CGImageSourceCreateThumbnailAtIndex
- `lora-dataset/lora-dataset/ImageCacheActor.swift` - Swift actor with LRU eviction, cost tracking, memory pressure monitoring
- `lora-dataset/lora-datasetTests/ImageLoaderTests.swift` - CGImageSource smoke test + nil-on-invalid test
- `lora-dataset/lora-datasetTests/ImageCacheActorTests.swift` - 8 tests: hit/miss, cost, LRU order, evictToFraction, clear, memory pressure warning/critical

## Decisions Made
- Used `[URL]` access-order array (front = MRU) alongside a dictionary for simpler LRU — avoids doubly-linked list complexity, acceptable for typical dataset sizes (hundreds of images)
- `budgetBytes` parameter accepts an optional override in the initializer so tests can create a small-budget cache without relying on physicalMemory
- `handleMemoryPressure(_:)` exposed as a non-private actor method so unit tests can exercise it directly

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed test PNG path from /tmp to temporaryDirectory**
- **Found during:** Task 1 (ImageLoaderTests — testLoadsWithCGImageSource)
- **Issue:** Test wrote to `/tmp/lora-dataset-test-image.png` but macOS sandbox blocks writes to `/tmp` in test runner context (NSCocoaErrorDomain Code=513 "No permission")
- **Fix:** Changed to `FileManager.default.temporaryDirectory.appendingPathComponent(...)` with UUID suffix for uniqueness
- **Files modified:** lora-dataset/lora-datasetTests/ImageLoaderTests.swift
- **Verification:** testLoadsWithCGImageSource passes — returns non-nil NSImage for valid PNG
- **Committed in:** e5325a6 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug in test infrastructure)
**Impact on plan:** Necessary fix — test would never pass without it. No scope creep.

## Issues Encountered
- macOS sandbox restricts test process from writing to `/tmp` — resolved by using `FileManager.default.temporaryDirectory` which is always writable in the sandbox

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- `ImageLoader.swift` and `ImageCacheActor.swift` are standalone, fully tested, and ready for Plan 02 wiring
- Plan 02 should integrate `ImageCacheActor` into `DatasetViewModel` and replace the `NSImage(contentsOf:)` call in `ContentView.loadImageForSelection()`
- Prefetch trigger points are documented in 10-CONTEXT.md

## Self-Check: PASSED

- FOUND: lora-dataset/lora-dataset/ImageLoader.swift
- FOUND: lora-dataset/lora-dataset/ImageCacheActor.swift
- FOUND: lora-dataset/lora-datasetTests/ImageLoaderTests.swift
- FOUND: lora-dataset/lora-datasetTests/ImageCacheActorTests.swift
- FOUND: .planning/phases/10-image-cache-prefetch/10-01-SUMMARY.md
- FOUND: commit e5325a6

---
*Phase: 10-image-cache-prefetch*
*Completed: 2026-03-16*
