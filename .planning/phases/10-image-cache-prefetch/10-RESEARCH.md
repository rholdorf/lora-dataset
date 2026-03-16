# Phase 10: Image Cache + Prefetch - Research

**Researched:** 2026-03-16
**Domain:** macOS image caching — CGImageSource / ImageIO, Swift structured concurrency actors, DispatchSource memory pressure
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Loading state on cache miss:**
- Subtle spinner overlay on dimmed previous image while loading
- Spinner appears only after 150ms delay — if image loads within that window, no spinner shown
- Instant swap (no fade/crossfade) when new image is ready
- On load failure (corrupt/unsupported file): centered system warning icon with filename below

**Cache scope across folders:**
- Clear entire cache when navigating to a different folder
- On folder open or return: immediately prefetch ±2 neighbors around the selected image
- Prefetch triggers on initial folder load, not just on subsequent navigation

**Memory budget strategy:**
- Adaptive sizing: 15% of physical RAM (e.g. 16 GB machine → ~2.4 GB cache)
- Tiered memory pressure response: warning → evict to 50% of budget; critical → evict everything
- Cache is completely invisible to the user — no UI indicators
- Use CGImageSource with kCGImageSourceThumbnailMaxPixelSize from the start (decode at display size, not full resolution)
- Memory accounting uses decoded pixel byte cost (width × height × 4)

**Rapid navigation behavior:**
- Show every image during fast arrow-key scrubbing if cached; skip uncached images and display wherever user stops
- Prefetch window (±2) chases current position — cancel stale prefetch tasks from passed positions
- Completed prefetch loads are kept in cache even if no longer in ±2 window (LRU evicts naturally)
- Zoom/pan resets to fit on every image change (preserve current behavior)

### Claude's Discretion
- Dirty-caption handling on folder switch (prompt to save vs. preserve in memory)
- Cache implementation details (data structure, threading model)
- Debug logging strategy for cache operations

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CACHE-01 | Images load from in-memory LRU cache with sub-50ms display on cache hit | Dictionary lookup O(1) + NSImage already decoded; 50ms is generous for a cache hit |
| CACHE-02 | Cache uses decoded pixel byte cost (width × height × 4) for memory accounting | CGImageSource exposes pixel dimensions via CGImageSourceCopyPropertiesAtIndex before full decode |
| CACHE-03 | ±2 neighboring images are prefetched in background on selection change | Task.detached per neighbor; track [UUID: Task<NSImage?, Never>] for cancellation |
| CACHE-04 | Images are decoded via CGImageSource at display size for faster loading | CGImageSourceCreateThumbnailAtIndex + kCGImageSourceThumbnailMaxPixelSize; verified pattern |
| CACHE-05 | Cache evicts entries under system memory pressure (partial on warning, full on critical) | DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical]) — Apple-native API |
| CACHE-06 | Stale prefetch tasks are cancelled when user navigates past them | task.cancel() on tasks whose URL is no longer in ±2 window; Task.isCancelled checked inside loader |
</phase_requirements>

---

## Summary

Phase 10 adds a two-layer performance subsystem: an in-memory LRU image cache that serves previously-seen images in under 50ms, and a background ±2-neighbor prefetcher that races to fill the cache before the user arrives. The entire system is invisible to the user except for a subtle 150ms-delayed spinner on cold misses.

The implementation rests on three Apple APIs that are purpose-built for this problem. `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` decodes images directly at display size — benchmarks show macOS JPEG processing at 40x faster than `NSImage(contentsOf:)` (16ms vs 628ms). `DispatchSource.makeMemoryPressureSource` delivers native `.warning`/`.critical` callbacks from the OS. Swift structured concurrency actors provide the correct threading model: a single `ImageCacheActor` serializes all cache mutations while prefetch tasks run detached on the cooperative thread pool.

The most important design decision is choosing a custom Swift actor over `NSCache` as the cache container. `NSCache`'s eviction order is not guaranteed to be LRU, and it can evict recently-added items before older ones — a known pathology documented by community benchmarks (2025 blog post, mjtsai.com). A `Dictionary<URL, CacheEntry>` inside an actor provides O(1) lookup with deterministic LRU via a doubly-linked access list, and lets us implement the user-specified cost accounting (width × height × 4) precisely.

**Primary recommendation:** Implement `ImageCacheActor` as a Swift actor with a `Dictionary` backed LRU (doubly-linked list for eviction order) + cost tracking. Load via `CGImageSourceCreateThumbnailAtIndex`. Monitor memory with `DispatchSource.makeMemoryPressureSource`. Integrate into `ContentView.loadImageForSelection()` as a single call-site replacement.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ImageIO (CGImageSource) | macOS built-in | Decode images at display size, read dimensions without full load | Apple-native; 40x faster than NSImage for JPEG on macOS; supports EXIF orientation |
| Dispatch (DispatchSource) | macOS built-in | Memory pressure monitoring (warning / critical events) | The only macOS API that delivers system-level memory pressure callbacks |
| Swift Concurrency (actor, Task) | Swift 5.9+ | Cache isolation, prefetch task management, cancellation | Replaces OperationQueue for this use case; built-in cooperative cancellation |
| Foundation (ProcessInfo) | macOS built-in | `physicalMemory` for adaptive cache budget | Direct API: `ProcessInfo.processInfo.physicalMemory` |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| AppKit (NSImage) | macOS built-in | Consumed by ZoomablePannableImage — no change needed | Already in project; cache produces NSImage, display layer unchanged |
| SwiftUI (ProgressView / overlay) | macOS built-in | 150ms-delayed spinner overlay on cache miss | Native SwiftUI overlay with Task sleep for delay |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Custom actor + Dictionary (LRU) | NSCache | NSCache eviction order is undefined, can evict recently-added items. Dictionary + actor is ~20 lines more but fully deterministic |
| CGImageSource thumbnail decode | NSImage(contentsOf:) | NSImage is 4–40x slower; no control over decode timing. CGImageSource is the correct tool for this requirement |
| DispatchSource.makeMemoryPressureSource | NSNotification.didReceiveMemoryWarning | The notification exists on iOS; macOS only delivers memory pressure through DispatchSource |
| Swift actor | DispatchQueue + DispatchSemaphore | Actor model is type-safe, eliminates lock/unlock errors, composes cleanly with async/await |

**Installation:** No third-party packages. All APIs are Apple frameworks built into macOS.

---

## Architecture Patterns

### Recommended Project Structure

```
lora-dataset/
├── ImageCacheActor.swift      # Actor: LRU cache + cost tracking + memory pressure
├── ImageLoader.swift          # Free function: CGImageSource decode at display size
├── ContentView.swift          # Modified: loadImageForSelection() → cache lookup + prefetch trigger
├── DatasetViewModel.swift     # Modified: navigateToFolder() triggers cache.clear() + initial prefetch
└── (existing files unchanged)
```

### Pattern 1: CGImageSource Thumbnail Decode

**What:** Decode an image file directly to display-sized pixels using ImageIO. Forces immediate decode (no lazy decompression on first draw) via `kCGImageSourceShouldCacheImmediately`.

**When to use:** Every image load — both on-demand and prefetch.

```swift
// Source: https://www.swiftjectivec.com/optimizing-images/
// Source: https://macguru.dev/fast-thumbnails-with-cgimagesource/
import ImageIO

func loadImage(url: URL, maxPixelSize: Int) -> NSImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

    let thumbOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,  // respect EXIF orientation
        kCGImageSourceShouldCacheImmediately: true,        // decode NOW, not on first draw
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    else { return nil }

    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}
```

**Important:** `kCGImageSourceShouldCache: false` on source creation prevents caching the raw undecoded data. `kCGImageSourceShouldCacheImmediately: true` on thumbnail creation forces decode at that instant (before returning to caller). This is the correct order.

### Pattern 2: Decoded Memory Cost

**What:** Compute cost in bytes before inserting into the cache, using pixel dimensions from the CGImage (already decoded).

**When to use:** Every cache insert.

```swift
// Cost in bytes for decoded RGBA image
func decodedByteCount(for cgImage: CGImage) -> Int {
    return cgImage.width * cgImage.height * 4
}
```

**Alternative — read dimensions without decoding (for capacity pre-check):**

```swift
// Source: https://macguru.dev/fast-thumbnails-with-cgimagesource/ (~2-4ms)
func imageDimensions(url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let w = props[kCGImagePropertyPixelWidth] as? Int,
          let h = props[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (w, h)
}
```

### Pattern 3: Swift Actor LRU Cache

**What:** A Swift actor that holds a Dictionary (O(1) lookup) + doubly-linked list (O(1) LRU eviction order) + total cost tracking. All mutations are actor-isolated.

**When to use:** This is `ImageCacheActor`.

```swift
// Conceptual skeleton — implementation detail left to planner
actor ImageCacheActor {
    private struct Entry {
        let image: NSImage
        let cost: Int   // width * height * 4
    }

    private var storage: [URL: Entry] = [:]
    private var accessOrder: [URL] = []          // front = most recent
    private var totalCost: Int = 0
    private let budgetBytes: Int                 // 0.15 * physicalMemory

    // O(1) hit path
    func image(for url: URL) -> NSImage? {
        guard let entry = storage[url] else { return nil }
        touch(url)   // move to front of accessOrder
        return entry.image
    }

    func insert(_ image: NSImage, cgImage: CGImage, for url: URL) {
        let cost = cgImage.width * cgImage.height * 4
        storage[url] = Entry(image: image, cost: cost)
        accessOrder.insert(url, at: 0)
        totalCost += cost
        evictIfNeeded()
    }

    func clear() {
        storage.removeAll()
        accessOrder.removeAll()
        totalCost = 0
    }

    func evictToFraction(_ fraction: Double) {
        let target = Int(Double(budgetBytes) * fraction)
        while totalCost > target, let oldest = accessOrder.last {
            evict(oldest)
        }
    }

    private func evictIfNeeded() { /* evict LRU until totalCost <= budgetBytes */ }
    private func evict(_ url: URL) { /* remove from storage + accessOrder, subtract cost */ }
    private func touch(_ url: URL) { /* move url to front of accessOrder */ }
}
```

### Pattern 4: Memory Pressure Monitoring

**What:** `DispatchSource.makeMemoryPressureSource` delivers OS memory pressure callbacks.

**When to use:** Set up once during `ImageCacheActor` init; cancel on deinit.

```swift
// Source: https://gist.github.com/networkextension/70b0ae8a5602ab40443ef27bd1364d86
// Source: https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:)
private func installMemoryPressureSource() {
    let source = DispatchSource.makeMemoryPressureSource(
        eventMask: [.warning, .critical],
        queue: .global(qos: .utility)
    )
    source.setEventHandler { [weak self] in
        let event = source.data   // NOTE: use .data not .mask
        Task {
            await self?.handleMemoryPressure(event)
        }
    }
    source.resume()
    self.memoryPressureSource = source
}

// Actor method — runs on actor executor
func handleMemoryPressure(_ event: DispatchSource.MemoryPressureEvent) {
    switch event {
    case .warning:
        evictToFraction(0.5)   // evict to 50% of budget
        print("[cache] memory warning — evicted to 50%")
    case .critical:
        clear()                // evict everything
        print("[cache] memory critical — cleared")
    default:
        break
    }
}
```

**Key gotcha:** Use `source.data` (current event) not `source.mask` (registered filter) inside the event handler. This is a documented community correction.

### Pattern 5: Prefetch Task Management

**What:** Dictionary of in-flight prefetch `Task` handles, keyed by URL. Stale tasks (outside ±2 window) are cancelled when selection changes.

**When to use:** In `DatasetViewModel` or `ContentView.onChange(of: selectedFileID)`.

```swift
// Track in-flight prefetch tasks
private var prefetchTasks: [URL: Task<Void, Never>] = [:]

func triggerPrefetch(around index: Int, in pairs: [ImageCaptionPair], displaySize: Int) {
    let window = max(0, index - 2)...min(pairs.count - 1, index + 2)
    let windowURLs = Set(window.map { pairs[$0].imageURL })

    // Cancel tasks that are no longer in window
    for (url, task) in prefetchTasks where !windowURLs.contains(url) {
        task.cancel()
        prefetchTasks.removeValue(forKey: url)
    }

    // Start tasks for window entries not yet cached or in-flight
    for url in windowURLs {
        guard prefetchTasks[url] == nil else { continue }
        guard await imageCache.image(for: url) == nil else { continue }
        prefetchTasks[url] = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return }
            if let image = loadImage(url: url, maxPixelSize: displaySize) {
                await imageCache.insert(image, for: url)
            }
            // Remove self from tracking dict on completion
        }
    }
}
```

**Note:** `Task.detached` matches the existing project pattern (`ContentView.loadImageForSelection` already uses it). Prefetch tasks run at `.utility` priority so they don't contend with UI.

### Pattern 6: NSImage and Swift Concurrency (Sendable)

**What:** NSImage is not `Sendable`. Passing it across actor boundaries requires an approach.

**Recommendation:** Use `extension NSImage: @unchecked @retroactive Sendable {}` at the top of `ImageCacheActor.swift`. This is safe here because:
- All NSImage instances produced by `loadImage()` are created on a background thread with no shared mutable state
- Once inserted into the cache, they are read-only
- The actor serializes all access

```swift
// ImageCacheActor.swift — at file scope
extension NSImage: @unchecked @retroactive Sendable {}
```

This is the standard community approach when NSImage is effectively immutable after creation. The alternative (converting to CGImage data and back) is unnecessary overhead.

### Pattern 7: 150ms-Delayed Spinner Overlay

**What:** Show a spinner only if image hasn't loaded within 150ms.

**When to use:** In the image display area of `DetailView` / `ContentView`.

```swift
// Pattern: show overlay state with delayed spinner
@State private var showSpinner: Bool = false

// When starting a load:
let loadID = currentLoadID  // UUID or Int counter
Task { @MainActor in
    try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
    guard self.currentLoadID == loadID else { return }  // selection didn't change
    guard self.loadedImage == nil else { return }        // image didn't load in time
    self.showSpinner = true
}

// Image display overlay:
ZoomablePannableImage(...)
    .overlay {
        if showSpinner {
            ProgressView()
                .background(Color.black.opacity(0.3))
        }
    }
```

**Note:** `ProgressView()` in a SwiftUI overlay renders `NSProgressIndicator` (spinning circle) natively. No NSViewRepresentable needed.

### Anti-Patterns to Avoid

- **NSCache for LRU:** NSCache eviction is non-deterministic — it can evict items in any order, including recently-used ones. Do not rely on it for LRU behavior.
- **NSImage(contentsOf:) for prefetch:** This bypasses display-size decoding. All loads, including prefetch, must go through `CGImageSourceCreateThumbnailAtIndex`.
- **Caching stale prefetch results after folder change:** `cache.clear()` must be called before populating `pairs` in `navigateToFolder()` — not after.
- **Running prefetch tasks at `.userInitiated` or `.userInteractive` priority:** This contends with UI rendering. Use `.utility`.
- **Forgetting `kCGImageSourceShouldCache: false` on source creation:** Without it, ImageIO caches the raw compressed data as well as the decoded thumbnail, doubling memory for no benefit.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Memory pressure detection | Polling timer checking available memory | DispatchSource.makeMemoryPressureSource | OS delivers events directly; polling is unreliable and wasteful |
| Display-size decoding | Custom image resize with NSImage/CoreGraphics | CGImageSourceCreateThumbnailAtIndex | ImageIO handles EXIF rotation, color profiles, format-specific codecs |
| Thread-safe cache mutations | Manual DispatchQueue + lock | Swift actor | Actor isolation is guaranteed by compiler; no lock/unlock errors possible |
| In-flight deduplication | Custom dictionary of completion callbacks | Task stored in prefetchTasks dict | Task is already a future; awaiting it from multiple sites is safe |

**Key insight:** ImageIO's CGImageSource is the only Apple API that separates source creation (metadata/dimensions) from decode (pixel data), enabling the precise timing control that `kCGImageSourceShouldCacheImmediately` provides.

---

## Common Pitfalls

### Pitfall 1: Wrong maxPixelSize for Thumbnail Decode

**What goes wrong:** Using a fixed value (e.g. 400) instead of the actual display container size. If the image panel is 600px wide but maxPixelSize is 400, zooming shows pixelation. If maxPixelSize equals the full image resolution (e.g. 4000px), the decode cost defeats the optimization.

**Why it happens:** The display size is dynamic (HSplitView can resize). A fixed constant seems simpler.

**How to avoid:** Pass the actual rendered frame size into `loadImage()`. The `ZoomablePannableImage` frame is `.frame(width: 400, height: 400)` in the current code — use `max(400, containerSize)` as a starting point, or use a device-pixel-aware value (`400 * NSScreen.main?.backingScaleFactor ?? 2.0`).

**Warning signs:** Users report images look blurry after zooming in.

### Pitfall 2: Cache Miss on Folder Revisit After Clear

**What goes wrong:** User navigates to subfolder and back. On return, the ±2 prefetch triggers, but because prefetch is async, the first image display is still a cache miss with visible latency.

**Why it happens:** `cache.clear()` + `scanCurrentDirectory()` + `selectedID = ...` all happen synchronously. The prefetch tasks are enqueued but haven't completed before `loadImageForSelection()` fires.

**How to avoid:** `loadImageForSelection()` itself checks the cache first. If miss, it loads synchronously (same as today), while prefetch fills neighbors concurrently. The 150ms spinner threshold means fast loads (local SSD, typical for LoRA datasets) remain invisible.

**Warning signs:** Spinner visible on re-navigation to previously-visited folders.

### Pitfall 3: source.mask vs source.data in Memory Pressure Handler

**What goes wrong:** Using `source.mask` in the DispatchSource event handler returns the *registered* event filter (e.g. `[.warning, .critical]`), not the current pressure level. The switch never matches correctly.

**Why it happens:** The API naming is misleading. `mask` sounds like "event mask received."

**How to avoid:** Always use `source.data` inside the event handler to get the current pressure event. Documented community correction — confirmed in GitHub gist.

**Warning signs:** Memory pressure responses don't fire even when system is under pressure.

### Pitfall 4: Wrong Image Shown After Rapid Navigation (Stale Task)

**What goes wrong:** User presses arrow key 5 times quickly. The 3rd image's prefetch task completes last, overwrites `loadedImage` with a stale result.

**Why it happens:** `Task.detached` results are dispatched to `MainActor.run` with a selection ID guard, but if the guard uses `URL` comparison instead of the load-start ID, a completed prefetch task for an earlier image can still set `loadedImage`.

**How to avoid:** In `loadImageForSelection()`, capture the `selectedFileID` UUID at task start. Check `self.selectedFileID == capturedID` before assigning `loadedImage`. This is already done in the current code — preserve this guard when refactoring.

**Warning signs:** Wrong image flashes briefly before correct image appears.

### Pitfall 5: NSImage Not Sendable Compiler Errors

**What goes wrong:** Swift 6 strict concurrency mode produces errors when passing NSImage across actor boundaries (e.g. from a `Task.detached` result into `ImageCacheActor.insert()`).

**Why it happens:** NSImage is not declared `Sendable` in AppKit.

**How to avoid:** Add `extension NSImage: @unchecked @retroactive Sendable {}` once at file scope in `ImageCacheActor.swift`. All NSImage instances from CGImageSource are effectively immutable after creation.

**Warning signs:** Build errors about "NSImage cannot be sent to actor-isolated context."

---

## Code Examples

### Full Load + Cache Lookup Pattern

```swift
// Source: Synthesis of ContentView.loadImageForSelection() + CGImageSource patterns
private func loadImageForSelection() {
    imageScale = 1.0
    imageOffset = .zero
    showSpinner = false

    guard let id = selectedFileID,
          let pair = vm.pairs.first(where: { $0.id == id }) else {
        loadedImage = nil
        return
    }

    let url = pair.imageURL
    let capturedID = id

    // Fast path: cache hit
    Task { @MainActor in
        if let cached = await vm.imageCache.image(for: url) {
            guard self.selectedFileID == capturedID else { return }
            self.loadedImage = cached
            return
        }
        // Slow path: cache miss — start delayed spinner
        let spinnerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard self.selectedFileID == capturedID, self.loadedImage == nil else { return }
            self.showSpinner = true
        }
        // Load off-main
        let image = await Task.detached(priority: .userInitiated) {
            loadImage(url: url, maxPixelSize: 800)
        }.value
        spinnerTask.cancel()
        guard self.selectedFileID == capturedID else { return }
        self.showSpinner = false
        self.loadedImage = image
        if let img = image {
            await vm.imageCache.insert(img, for: url)
        }
        // Trigger prefetch for neighbors
        await vm.triggerPrefetch(around: capturedID)
    }
}
```

### Adaptive Budget Calculation

```swift
// Source: ProcessInfo.processInfo.physicalMemory — Apple docs
let budgetBytes: Int = {
    let physical = ProcessInfo.processInfo.physicalMemory   // UInt64, bytes
    return Int(Double(physical) * 0.15)                     // 15% of physical RAM
}()
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSImage(contentsOf:) for all loads | CGImageSourceCreateThumbnailAtIndex | Recommended since WWDC 2018 "Images and Graphics Best Practices" | 4–40x faster decode; precise decode timing control |
| NSCache for image caching | Custom actor + Dictionary | Swift Concurrency era (2021+) | Deterministic LRU; integrates cleanly with async/await |
| OperationQueue for prefetch | Swift Task with .cancel() | Swift 5.5 (2021) | Cooperative cancellation; no OperationQueue boilerplate |
| DispatchQueue + NSLock for thread safety | Swift actor | Swift 5.5 (2021) | Compiler-enforced isolation; eliminates lock/unlock errors |

**Deprecated/outdated:**
- `NSImage(contentsOf:)` for performance-sensitive loading: Still works but bypasses all ImageIO optimizations. Do not use for cache loads.
- `NSCache` for LRU-ordered image cache: Eviction order is undefined. Acceptable for simple "keep some images in memory" use cases, not for cost-tracked LRU with a memory budget.

---

## Open Questions

1. **Display container size for maxPixelSize**
   - What we know: Current code has `.frame(width: 400, height: 400)` for the image panel, but HSplitView means actual rendered size varies.
   - What's unclear: Should we decode at 2x backing scale (800px) unconditionally, or dynamically track frame size?
   - Recommendation: Use a fixed `800` (2x retina of 400px frame) as a reasonable default. This handles most cases without dynamic tracking. Can be refined later if users report blurriness on large displays.

2. **Dirty-caption handling on folder switch**
   - What we know: `editingIsDirty` flag exists; `navigateToFolder()` calls `scanCurrentDirectory()` which overwrites `pairs`.
   - What's unclear: Should dirty caption text be preserved in-memory across folder switch, or prompt user?
   - Recommendation (Claude's discretion): Prompt with a simple "Save / Discard" sheet before clearing pairs. This prevents silent data loss and matches macOS document-model conventions.

3. **`@unchecked Sendable` vs Swift 6 concurrency mode**
   - What we know: Project currently uses Swift 5 concurrency mode (no `SWIFT_STRICT_CONCURRENCY = complete` in project).
   - What's unclear: Will the project ever enable strict mode? If so, `@unchecked Sendable` is the right fix.
   - Recommendation: Add the extension now regardless — it's the correct declaration for this use pattern.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Swift Testing (import Testing) — already in use |
| Config file | None — Xcode scheme-based |
| Quick run command | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests` |
| Full suite command | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CACHE-01 | Cache hit returns NSImage without calling loadImage | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageCacheActorTests/testCacheHitReturnsCachedImage` | ❌ Wave 0 |
| CACHE-02 | Cost accounting uses width×height×4 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageCacheActorTests/testCostAccounting` | ❌ Wave 0 |
| CACHE-03 | Prefetch enqueues tasks for ±2 neighbors | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageCacheActorTests/testPrefetchEnqueuedForNeighbors` | ❌ Wave 0 |
| CACHE-04 | loadImage() uses CGImageSource (smoke) | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageLoaderTests/testLoadsWithCGImageSource` | ❌ Wave 0 |
| CACHE-05 | Warning evicts to 50% budget; critical clears all | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageCacheActorTests/testMemoryPressureEviction` | ❌ Wave 0 |
| CACHE-06 | Tasks outside ±2 window are cancelled | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageCacheActorTests/testStalePrefetchCancelled` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests`
- **Per wave merge:** `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `lora-datasetTests/ImageCacheActorTests.swift` — covers CACHE-01, CACHE-02, CACHE-03, CACHE-05, CACHE-06
- [ ] `lora-datasetTests/ImageLoaderTests.swift` — covers CACHE-04 (smoke test that loadImage returns non-nil NSImage for a known test image)

*(No framework install needed — Swift Testing is already in use in lora_datasetTests.swift and CaptionEditorViewTests.swift)*

---

## Sources

### Primary (HIGH confidence)
- Apple Developer Documentation: `CGImageSource` — `kCGImageSourceThumbnailMaxPixelSize`, `kCGImageSourceShouldCacheImmediately`, `kCGImageSourceCreateThumbnailFromImageAlways`
- Apple Developer Documentation: `DispatchSource.makeMemoryPressureSource(eventMask:queue:)` — event mask values `.warning`, `.critical`
- Apple Developer Documentation: `ProcessInfo.physicalMemory` — UInt64 physical RAM in bytes
- https://developer.apple.com/documentation/appkit/nsprogressindicator — NSProgressIndicator for spinner overlay

### Secondary (MEDIUM confidence)
- https://www.swiftjectivec.com/optimizing-images/ — CGImageSource downsampling code pattern + memory footprint comparison; verified against Apple docs
- https://macguru.dev/fast-thumbnails-with-cgimagesource/ — `kCGImageSourceCreateThumbnailFromImageAlways` rationale + benchmark data (40x JPEG speedup); consistent with Apple docs
- https://forums.swift.org/t/structured-caching-in-an-actor/65501 — Actor-based cache pattern with enum CacheEntry states; WWDC 2023 engineer recommendation
- https://forums.swift.org/t/updating-imagedownloader-actor-sample-to-support-cancellation/85126 — CountedTask pattern for actor cache cancellation
- https://gist.github.com/networkextension/70b0ae8a5602ab40443ef27bd1364d86 — DispatchSource memory pressure example with `source.data` correction

### Tertiary (LOW confidence)
- https://mjtsai.com/blog/2025/05/09/nscache-and-lrucache/ — NSCache non-deterministic eviction pathology; single blog source, consistent with known NSCache behavior

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all APIs are Apple-native, well-documented, verified against official docs
- Architecture: HIGH — CGImageSource + actor + DispatchSource is the canonical modern macOS approach; patterns verified in Swift Forums and official docs
- Pitfalls: HIGH — `source.data` vs `source.mask` bug is a community-verified gotcha; NSImage Sendable issue is a compiler-level fact; stale task guard already exists in current codebase

**Research date:** 2026-03-16
**Valid until:** 2027-03-16 (stable Apple APIs, unlikely to change; Swift concurrency actor model is stable)
