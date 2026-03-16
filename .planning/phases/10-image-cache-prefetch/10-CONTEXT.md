# Phase 10: Image Cache + Prefetch - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Sub-50ms image display via in-memory LRU cache with background neighbor prefetch. Users experience Finder-speed navigation with no perceptible load delay. Covers requirements CACHE-01 through CACHE-06.

</domain>

<decisions>
## Implementation Decisions

### Loading state on cache miss
- Subtle spinner overlay on dimmed previous image while loading
- Spinner appears only after 150ms delay — if image loads within that window, no spinner shown
- Instant swap (no fade/crossfade) when new image is ready
- On load failure (corrupt/unsupported file): centered system warning icon with filename below

### Cache scope across folders
- Clear entire cache when navigating to a different folder
- On folder open or return: immediately prefetch ±2 neighbors around the selected image
- Prefetch triggers on initial folder load, not just on subsequent navigation

### Memory budget strategy
- Adaptive sizing: 15% of physical RAM (e.g. 16 GB machine → ~2.4 GB cache)
- Tiered memory pressure response: warning → evict to 50% of budget; critical → evict everything
- Cache is completely invisible to the user — no UI indicators
- Use CGImageSource with kCGImageSourceThumbnailMaxPixelSize from the start (decode at display size, not full resolution)
- Memory accounting uses decoded pixel byte cost (width × height × 4)

### Rapid navigation behavior
- Show every image during fast arrow-key scrubbing if cached; skip uncached images and display wherever user stops
- Prefetch window (±2) chases current position — cancel stale prefetch tasks from passed positions
- Completed prefetch loads are kept in cache even if no longer in ±2 window (LRU evicts naturally)
- Zoom/pan resets to fit on every image change (preserve current behavior)

### Claude's Discretion
- Dirty-caption handling on folder switch (prompt to save vs. preserve in memory)
- Cache implementation details (data structure, threading model)
- Debug logging strategy for cache operations

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ContentView.loadImageForSelection()`: Current async image loading via `Task.detached { NSImage(contentsOf: url) }` — replace with cache lookup + prefetch trigger
- `selectNextPair()` / `selectPreviousPair()`: Existing navigation methods — neighbor indices are directly accessible from sorted `pairs` array
- `ZoomablePannableImage`: Accepts `NSImage` — cache just needs to provide NSImage faster, no changes needed to display layer

### Established Patterns
- `@MainActor` ViewModel with `@Published` properties — cache updates should follow this pattern
- `Task.detached` for off-main-thread work — existing pattern for async image loading
- `isUpdatingProgrammatically` flag pattern — for preventing feedback loops during state sync
- Debug prints with `[prefix]` convention (e.g. `[saveSelected]`) — use `[cache]` prefix for cache logging

### Integration Points
- `ContentView.loadImageForSelection()` — primary integration point, replace direct `NSImage(contentsOf:)` with cache lookup
- `DatasetViewModel.navigateToFolder()` — trigger cache clear + prefetch on folder change
- `DatasetViewModel.scanCurrentDirectory()` — trigger initial prefetch after pairs are populated
- `ContentView.onChange(of: selectedFileID)` — where prefetch trigger on selection change should hook in

</code_context>

<specifics>
## Specific Ideas

No specific requirements — open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-image-cache-prefetch*
*Context gathered: 2026-03-16*
