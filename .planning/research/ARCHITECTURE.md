# Architecture Research

**Domain:** Native macOS SwiftUI/AppKit — Image Cache + Filesystem Watchdog integration
**Researched:** 2026-03-16
**Confidence:** HIGH for cache placement and threading model; MEDIUM for DispatchSource directory watching event semantics (Apple docs require JavaScript, verified via community sources)

---

## Context: Existing Architecture (v1.4 baseline)

```
ContentView (@StateObject vm: DatasetViewModel)
  NavigationSplitView
    ├── Sidebar (SwiftUI List)
    │     ├── FolderTreeView → FolderNodeView (SwiftUI)
    │     └── File rows (ForEach over vm.pairs)
    └── DetailView
          ├── ZoomablePannableImage (NSViewRepresentable → ZoomableImageNSView)
          └── CaptionEditingContainer → CaptionEditorView (NSViewRepresentable → NSTextView)

DatasetViewModel (@MainActor ObservableObject)
  @Published: pairs, selectedID, folderTree, directoryURL, expandedPaths,
              captionReloadToken, editingIsDirty
  liveEditingText: String   (non-published, avoids per-keystroke renders)
  securedDirectoryURL: URL? (security-scoped bookmark, kept active)

Image loading (current):
  ContentView.loadImageForSelection()
    Task.detached { NSImage(contentsOf:) } → await MainActor.run { self.loadedImage = image }
```

Key constraint: `DatasetViewModel` is `@MainActor`. File I/O already happens on a detached task and hops back to main actor for assignment. The new cache and watchdog must fit cleanly into this threading model.

---

## System Overview: After v1.5

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           SwiftUI Layer                                  │
│  ContentView                                                             │
│    onChange(of: vm.selectedID) → triggers prefetch in DatasetViewModel  │
│    loadedImage: NSImage? ← served from ImageCache (via vm method)       │
├─────────────────────────────────────────────────────────────────────────┤
│                     DatasetViewModel (@MainActor)                        │
│    selectedID.didSet → prefetch(around: selectedIndex)                  │
│    loadImageForSelection() → ImageCache.image(for:) → assign loadedImage│
│    handleFSEvent(at: URL) → rescan / reload caption / evict cache       │
├──────────────────────────┬──────────────────────────────────────────────┤
│      ImageCache           │          FilesystemWatchdog                  │
│  (actor, separate class) │       (class, owns DispatchSource)           │
│  NSCache<NSURL, NSImage>  │  DispatchSource on securedDirectoryURL      │
│  prefetch(urls:)          │  .write eventMask (detects adds/dels/writes) │
│  evict(url:)              │  → Task { @MainActor in vm.handleFSEvent() } │
│  Memory pressure aware    │                                              │
└──────────────────────────┴──────────────────────────────────────────────┘
```

---

## Component Responsibilities

| Component | Status | Responsibility |
|-----------|--------|----------------|
| `ImageCache` | New | NSImage in-memory cache, prefetch queue, LRU eviction via NSCache, memory pressure response |
| `FilesystemWatchdog` | New | DispatchSourceFileSystemObject on current directory; delivers typed events to DatasetViewModel via async callback |
| `DatasetViewModel` | Modify | Owns ImageCache and FilesystemWatchdog instances; triggers prefetch on selection change; handles FS events |
| `ContentView` | Modify (minor) | `loadImageForSelection()` asks ViewModel for image (from cache) instead of loading itself |

---

## Decision 1: Cache Placement — Separate Class, Owned by ViewModel

**Recommendation: `actor ImageCache` as a separate class, held by `DatasetViewModel`.**

Rationale:
- `DatasetViewModel` is `@MainActor`. NSImage loading is CPU/IO work — it must not block the main actor. An `actor ImageCache` runs on its own executor, keeping loading off the main thread.
- Holding the cache instance inside `DatasetViewModel` (rather than a global singleton or environment object) keeps the lifecycle tied to the ViewModel. When the ViewModel deinits, the cache deinits. This avoids stale cache entries across directory changes — eviction is trivial: replace the cache object on `navigateToFolder()`.
- The ViewModel coordinates prefetch (it knows selection index and `pairs` array), so it is the natural trigger site. The cache does not need to know about selection; it only answers "give me this image" and "prefetch these URLs."

**Rejected: Embedding NSCache directly in DatasetViewModel**
DatasetViewModel is `@MainActor`. NSImage loading inside an `@MainActor` method would block the main thread. You cannot call `Task.detached` from within `@MainActor` and write back to a property on the same `@MainActor` instance without a hop — the detached task still needs `await MainActor.run {}`. An actor-isolated `ImageCache` makes the async boundary explicit and enforced by the compiler.

**Rejected: Global singleton / environment object**
Global cache survives directory changes. Stale NSImage for a path in a different dataset would be served on session restore. The lifecycle coupling to ViewModel avoids this silently.

---

## Decision 2: Watchdog Placement — Separate Class, Owned by ViewModel

**Recommendation: `class FilesystemWatchdog` (not an actor), held by `DatasetViewModel`.**

Rationale:
- `DispatchSourceFileSystemObject` is a GCD primitive. It cannot be used inside a Swift actor directly — actors do not provide a GCD queue you can pass to `DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask:queue:)`. A plain class with a private `DispatchQueue` for the source is the correct pattern.
- The watchdog delivers events to the ViewModel via an async closure that hops to `@MainActor`:

```swift
source.setEventHandler {
    Task { @MainActor in
        self.viewModel?.handleFSEvent()
    }
}
```

This is the standard bridge between GCD callbacks and `@MainActor` Swift concurrency (verified: `Task { @MainActor in }` from a non-isolated context correctly dispatches to the main actor).

- The watchdog watches one directory at a time. `DatasetViewModel.navigateToFolder()` stops the old watchdog and starts a new one pointed at the new directory.

**What DispatchSource `.write` on a directory detects:**
Watching a directory descriptor with `.write` eventMask fires when files are added, deleted, or renamed within that directory (directory entry changes). It does NOT fire for modifications to file content within the directory — content changes require watching the individual file descriptor. For the use case of detecting "a .txt/.caption file was externally modified" (e.g., by a training script writing captions), you need a separate source per caption file, or accept a polling fallback for content changes.

**Recommended approach for v1.5:**
- Directory-level `.write` source: detects additions, deletions, renames → trigger `scanCurrentDirectory()` to refresh pairs list.
- For detecting caption file content changes (a separate file was rewritten externally): watch the selected caption file's descriptor with `.write`. When it fires and the selected pair matches, reload caption text.
- Do not watch all N caption files simultaneously — use a single file-level watcher that follows `vm.selectedID` changes.

---

## New Component Specifications

### `actor ImageCache`

```swift
actor ImageCache {
    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    init() {
        cache.countLimit = 50          // images
        cache.totalCostLimit = 200 * 1024 * 1024  // 200 MB
    }

    func image(for url: URL) async -> NSImage? {
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        if let task = inFlight[url] { return await task.value }
        let task = Task.detached(priority: .userInitiated) {
            NSImage(contentsOf: url)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let img = result {
            let cost = Int(img.size.width * img.size.height * 4)  // ~bytes
            cache.setObject(img, forKey: url as NSURL, cost: cost)
        }
        return result
    }

    func prefetch(urls: [URL]) {
        for url in urls {
            guard cache.object(forKey: url as NSURL) == nil,
                  inFlight[url] == nil else { continue }
            let task = Task.detached(priority: .background) {
                NSImage(contentsOf: url)
            }
            inFlight[url] = task
            Task {
                let result = await task.value
                inFlight[url] = nil
                if let img = result {
                    let cost = Int(img.size.width * img.size.height * 4)
                    cache.setObject(img, forKey: url as NSURL, cost: cost)
                }
            }
        }
    }

    func evict(url: URL) {
        cache.removeObject(forKey: url as NSURL)
        inFlight[url]?.cancel()
        inFlight[url] = nil
    }

    func evictAll() {
        cache.removeAllObjects()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }
}
```

**Memory pressure:** NSCache handles this automatically. When the system signals memory pressure, NSCache evicts objects before the app receives a memory warning. Setting `totalCostLimit` (bytes) is more precise than `countLimit` (object count) for variable-size images. Use both: `countLimit` as a safety cap on object count, `totalCostLimit` as the memory budget.

**In-flight deduplication:** The `inFlight` dictionary prevents two callers from loading the same URL concurrently. The second caller awaits the same Task. This is critical during prefetch — if the user navigates quickly, the cache-miss path for the selected image is already in flight from prefetch.

**Thread safety:** Because `ImageCache` is an `actor`, all properties (`cache`, `inFlight`) are actor-isolated. NSCache itself is thread-safe, but the combined cache+inFlight check must be atomic — the actor boundary provides that atomicity.

---

### `class FilesystemWatchdog`

```swift
final class FilesystemWatchdog {
    private var dirSource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var dirDescriptor: Int32 = -1
    private var fileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "com.lora-dataset.fswatchdog",
                                      qos: .utility)

    var onDirectoryChanged: (() -> Void)?       // fires on add/delete/rename
    var onSelectedFileChanged: (() -> Void)?    // fires when watched caption changes

    func watchDirectory(_ url: URL) {
        stopDirectory()
        dirDescriptor = open(url.path, O_EVTONLY)
        guard dirDescriptor >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: dirDescriptor,
            eventMask: .write,     // directory write = entries added/deleted/renamed
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.onDirectoryChanged?()
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.dirDescriptor, fd >= 0 { close(fd) }
            self?.dirDescriptor = -1
        }
        src.resume()
        dirSource = src
    }

    func watchFile(_ url: URL) {
        stopFile()
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.onSelectedFileChanged?()
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 { close(fd) }
            self?.fileDescriptor = -1
        }
        src.resume()
        fileSource = src
    }

    func stopDirectory() {
        dirSource?.cancel()
        dirSource = nil
    }

    func stopFile() {
        fileSource?.cancel()
        fileSource = nil
    }

    func stop() { stopDirectory(); stopFile() }

    deinit { stop() }
}
```

**O_EVTONLY flag:** Opens the path for event-only notification. Does not hold the file open for reading/writing. This is correct for monitoring — prevents the app from blocking filesystem operations (e.g., the volume cannot be unmounted while a regular file descriptor is open).

**eventMask `.write` on a directory:** Fires when directory entries change (files added, deleted, renamed within that directory). Does NOT fire for modifications to file content inside the directory. This is the correct mask for detecting "a new image appeared" or "a caption was deleted."

**eventMask `[.write, .delete, .rename]` on a file:** Covers external editors that write via temp file + rename (atomic write pattern), direct writes, and deletion. This covers most editors including training scripts.

---

## Changes to DatasetViewModel

### New Properties

```swift
// Cache — replaced on directory change
private let imageCache = ImageCache()

// Watchdog — two-level: directory structure + selected file content
private let watchdog = FilesystemWatchdog()
```

### Modified: selectedID.didSet — Prefetch Trigger

```swift
@Published var selectedID: UUID? = nil {
    didSet {
        UserDefaults.standard.set(selectedPair?.imageURL.path,
                                  forKey: "lastSelectedImagePath")
        updateQuickLookIfVisible()
        triggerPrefetch()          // NEW
        watchSelectedCaptionFile() // NEW
    }
}
```

### New Method: triggerPrefetch

```swift
private func triggerPrefetch() {
    guard let id = selectedID,
          let idx = pairs.firstIndex(where: { $0.id == id }) else { return }

    // Prefetch 2 images ahead and 1 behind
    let range = max(0, idx - 1)...min(pairs.count - 1, idx + 2)
    let urlsToCache = range
        .filter { $0 != idx }  // skip selected — it's loaded immediately
        .map { pairs[$0].imageURL }

    Task {
        await imageCache.prefetch(urls: urlsToCache)
    }
}
```

**Window size rationale:** 2 ahead + 1 behind matches the pattern of linear dataset review. The selected image is loaded immediately (not via prefetch). Background priority keeps prefetch from competing with the selected image load.

### New Method: loadImage (replaces ContentView logic)

Move image loading responsibility from ContentView into the ViewModel so it can use the cache:

```swift
func loadImage(for pair: ImageCaptionPair) async -> NSImage? {
    return await imageCache.image(for: pair.imageURL)
}
```

ContentView's `loadImageForSelection()` becomes:

```swift
private func loadImageForSelection() {
    imageScale = 1.0
    imageOffset = .zero
    guard let id = selectedFileID,
          let pair = vm.pairs.first(where: { $0.id == id }) else {
        loadedImage = nil
        return
    }
    Task {
        let image = await vm.loadImage(for: pair)
        await MainActor.run {
            guard self.selectedFileID == id else { return }
            self.loadedImage = image
        }
    }
}
```

The `Task` here (without `.detached`) inherits the actor context of `ContentView` (which is `@MainActor`). Calling `vm.loadImage(for:)` suspends and hops to the `ImageCache` actor automatically. This is correct structured concurrency.

### New Method: watchSelectedCaptionFile

```swift
private func watchSelectedCaptionFile() {
    guard let pair = selectedPair else {
        watchdog.stopFile()
        return
    }
    watchdog.watchFile(pair.captionURL)
    watchdog.onSelectedFileChanged = { [weak self] in
        Task { @MainActor [weak self] in
            self?.reloadCaptionForSelected()
        }
    }
}
```

### Modified: chooseDirectory / navigateToFolder — Start Watchdog

```swift
// After scanning:
imageCache.evictAll()  // clear cache on directory change
watchdog.watchDirectory(folder)
watchdog.onDirectoryChanged = { [weak self] in
    Task { @MainActor [weak self] in
        self?.scanCurrentDirectory()
    }
}
```

**Evicting on directory change** prevents serving stale images from a previous folder if paths happen to collide across datasets.

### Modified: saveSelected — Suppress Watchdog Loop

After saving a caption, the watchdog will fire (the file was written). This would trigger `reloadCaptionForSelected()` unnecessarily and lose the dirty state check. Suppress:

```swift
func saveSelected() {
    watchdog.stopFile()      // suppress the FS event from our own write
    defer {
        watchdog.watchFile(selectedPair?.captionURL ?? URL(fileURLWithPath: ""))
    }
    // ... existing save logic ...
}
```

Alternatively: add a `isSaving: Bool` flag and guard in `onSelectedFileChanged`. Either approach works; the `stopFile/resume` approach is simpler and has no race conditions because all of this runs on `@MainActor`.

---

## Data Flow: Image Load with Cache

```
User presses arrow key / clicks sidebar item
    ↓
ContentView.onChange(of: selectedFileID)
    ↓
vm.selectedID = selectedFileID  (@MainActor)
    ↓
selectedID.didSet fires (on @MainActor)
    ├── triggerPrefetch() — Task { await imageCache.prefetch(neighbor URLs) }
    └── watchSelectedCaptionFile() — watchdog points to new caption file
    ↓
ContentView.loadImageForSelection()
    ↓
Task { let img = await vm.loadImage(for: pair) }
    ↓ (suspends, hops to ImageCache actor)
ImageCache.image(for: url)
    ├── Cache HIT → return NSImage immediately (sub-millisecond)
    └── Cache MISS → Task.detached { NSImage(contentsOf:) } → store → return
    ↓ (hops back to @MainActor)
self.loadedImage = img  → DetailView re-renders with new image
```

---

## Data Flow: Filesystem Event

```
External process modifies caption file (e.g., training script)
    ↓
DispatchSourceFileSystemObject fires (.write on caption file descriptor)
    ↓  [on watchdog's DispatchQueue (utility QoS)]
onSelectedFileChanged closure
    ↓
Task { @MainActor in vm.reloadCaptionForSelected() }
    ↓  [hops to main actor]
reloadCaptionForSelected() → reads file → updates pairs[idx] → increments captionReloadToken
    ↓
CaptionEditingContainer.onChange(of: vm.captionReloadToken) → syncFromVM()
    ↓
NSTextView displays updated caption
```

```
External process adds/removes image file in watched directory
    ↓
DispatchSourceFileSystemObject fires (.write on directory descriptor)
    ↓  [on watchdog's DispatchQueue]
onDirectoryChanged closure
    ↓
Task { @MainActor in vm.scanCurrentDirectory() }
    ↓
scanCurrentDirectory() → pairs refreshed → UI updates
```

---

## Architectural Patterns

### Pattern 1: Actor-Isolated Cache with In-Flight Deduplication

**What:** `ImageCache` is a Swift `actor`. Cache lookups and stores are actor-isolated. A `[URL: Task<NSImage?, Never>]` dictionary deduplicates concurrent requests for the same URL.

**When to use:** Any shared mutable state accessed from multiple async contexts. The `actor` keyword enforces this automatically — no explicit locking needed.

**Trade-offs:** Small overhead vs. NSLock-based class. The overhead is negligible for image loading where I/O dominates. The compiler-enforced safety is worth the minor performance cost.

### Pattern 2: GCD → @MainActor Bridge

**What:** DispatchSource callbacks (GCD) are delivered on a background DispatchQueue. Bridge to `@MainActor` via `Task { @MainActor in ... }` from within the GCD handler.

**When to use:** Any time a system callback (GCD, completion handler, delegate) needs to update `@MainActor`-isolated state.

**Trade-offs:** `Task { @MainActor in }` enqueues asynchronously — it does not execute synchronously when the GCD handler fires. This means there is a small delay (one run-loop iteration) between the FS event and the UI update. Acceptable for filesystem notifications, which have inherently high latency anyway (event coalescing by the OS).

**Example:**
```swift
source.setEventHandler { [weak self] in
    // This closure runs on watchdog's DispatchQueue
    Task { @MainActor [weak self] in
        // This block runs on main actor
        self?.viewModel?.handleFSEvent()
    }
}
```

### Pattern 3: Watchdog Suppression on Self-Write

**What:** Before writing a file that the watchdog monitors, temporarily stop the file watcher. Resume after the write (via `defer` or explicit call).

**When to use:** Any time the app writes to a file it is also watching. Prevents a feedback loop where the app's own save triggers a reload.

**Trade-offs:** Between `stopFile()` and the deferred `watchFile()`, an external write would be missed. The window is tiny (the time to write a small text file). Acceptable for caption files.

---

## File Structure Changes

```
lora-dataset/lora-dataset/
├── DatasetViewModel.swift       # Modified: cache/watchdog integration
├── ContentView.swift            # Modified: loadImageForSelection uses cache
├── ImageCache.swift             # NEW: actor ImageCache
├── FilesystemWatchdog.swift     # NEW: class FilesystemWatchdog
├── ImageCaptionPair.swift       # Unchanged
├── ZoomablePannableImage.swift  # Unchanged
├── CaptionEditorView.swift      # Unchanged
├── QLPreviewHelper.swift        # Unchanged
└── lora_datasetApp.swift        # Unchanged
```

---

## Build Order

Build order is determined by dependency chain:

```
1. ImageCache.swift  (standalone actor, no dependencies)
   - No imports of app types needed
   - Can be built and unit-tested in isolation

2. FilesystemWatchdog.swift  (standalone class, no dependencies on app types)
   - Depends only on Foundation/Dispatch
   - Can be tested with real directories

3. DatasetViewModel.swift  (depends on ImageCache + FilesystemWatchdog)
   - Add cache and watchdog properties
   - Add triggerPrefetch(), watchSelectedCaptionFile(), handleFSEvent()
   - Modify navigateToFolder() and chooseDirectory() to start watchdog
   - Modify saveSelected() to suppress watchdog during write

4. ContentView.swift  (depends on updated DatasetViewModel API)
   - Update loadImageForSelection() to call vm.loadImage(for:)
   - Minimal change: the async/await structure is already present
```

Dependencies flow strictly downward. Steps 1 and 2 have no cross-dependency and can be written in parallel.

---

## Integration Points Summary

| What | New or Modified | Key Change |
|------|----------------|------------|
| `ImageCache.swift` | New | Actor-isolated NSCache + in-flight deduplication |
| `FilesystemWatchdog.swift` | New | DispatchSource wrapper; delivers events via async closures |
| `DatasetViewModel.swift` | Modified | Owns cache + watchdog; triggers prefetch on selectedID change |
| `ContentView.swift` | Modified (minor) | `loadImageForSelection()` uses async cache lookup |

Total new files: **2**
Total modified files: **2** (`DatasetViewModel.swift`, `ContentView.swift`)

---

## Anti-Patterns

### Anti-Pattern 1: Embedding Loading Logic Inside @MainActor ViewModel

**What people do:** Call `NSImage(contentsOf:)` directly inside a `@MainActor` method.

**Why it's wrong:** Blocks the main thread during image decode. For large PNG/TIFF files this is 100ms+. UI freezes during navigation.

**Do this instead:** Load inside an `actor` method that suspends (runs on actor's background executor) or use `Task.detached(priority:)`. The `ImageCache` actor pattern handles this automatically.

### Anti-Pattern 2: Watching Individual Files for All Pairs

**What people do:** Create one `DispatchSourceFileSystemObject` per image/caption file to detect any change.

**Why it's wrong:** A dataset folder with 500 images would open 1000+ file descriptors simultaneously. macOS per-process file descriptor limits are typically 10,240 by default, but opening this many for event-only purposes is wasteful and may interfere with normal file operations.

**Do this instead:** Watch the directory with `.write` (one descriptor) for structural changes. Watch only the selected caption file (one descriptor) for content changes. Total: 2 descriptors.

### Anti-Pattern 3: Using Task.detached Inside @MainActor ViewModel for Cache Access

**What people do:** `Task.detached { let img = await cache.image(for:) }` from a `@MainActor` context.

**Why it's wrong:** `Task.detached` loses the task's priority and cancellation token. The detached task is not cancelled if the user navigates away before the image loads. Result: stale image delivered after selection has changed.

**Do this instead:** Use `Task { }` (inheriting actor context), which propagates cancellation. Guard against stale delivery with `guard self.selectedFileID == id else { return }` inside `MainActor.run`.

### Anti-Pattern 4: Recreating DispatchSource on Every Selection Change

**What people do:** Cancel and recreate the directory-level DispatchSource whenever `selectedID` changes.

**Why it's wrong:** The directory watcher should persist across selection changes — the directory hasn't changed, just the selected file. Unnecessary cancel/resume cycles add overhead and may miss events fired during the recreation window.

**Do this instead:** The directory watcher lives for the duration of a folder being active. Only the file watcher (for caption content) is recreated on each selection change.

### Anti-Pattern 5: Not Handling the Self-Write Echo

**What people do:** Save a caption, then ignore the FS event that fires from that write.

**Why it's wrong:** `reloadCaptionForSelected()` will run immediately after save, overwriting the in-memory state. If `captionText` was modified after save (edge case), it would be lost. Even without that edge case, the reload is a wasted file read that fires `captionReloadToken`, causing `CaptionEditingContainer` to re-sync unnecessarily.

**Do this instead:** Stop the file watcher before save, restart after (with `defer`). The suppression window is bounded by the write operation itself.

---

## Scaling Considerations

This is a single-user desktop app. "Scaling" means handling larger datasets gracefully.

| Dataset Size | Current Behavior | With v1.5 Cache |
|--------------|-----------------|-----------------|
| 50 images | Fast (small files) | Instant (all cached quickly) |
| 500 images | Acceptable (load on demand) | Instant for neighbors; misses amortized |
| 5,000 images | Load lag on each navigation step | Same — only 3 images cached around selection |
| 50,000 images | Same (no directory-level lag change) | Same; NSCache evicts old entries automatically |

NSCache with `countLimit = 50` and `totalCostLimit = 200 MB` keeps memory bounded regardless of dataset size. The prefetch window of ±2 images means "next image" is nearly always a cache hit.

---

## Sources

- [DispatchSource: Detecting changes in files and folders in Swift — SwiftRocks](https://swiftrocks.com/dispatchsource-detecting-changes-in-files-and-folders-in-swift)
- [Monitoring a folder for changes in iOS — Daniel Galasko / Medium](https://medium.com/over-engineering/monitoring-a-folder-for-changes-in-ios-dc3f8614f902)
- [DispatchSourceFileSystemObject — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatchsourcefilesystemobject)
- [Monitoring Files Using Dispatch Sources — agostini.tech](https://agostini.tech/2017/08/06/monitoring-files-using-dispatch-sources/)
- [Reacting to File Changes — SwiftToolkit.dev](https://www.swifttoolkit.dev/posts/file-monitor)
- [Reusable Image Cache in Swift — On Swift Wings](https://www.onswiftwings.com/posts/reusable-image-cache/)
- [NSCache — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/nscache)
- [MainActor usage in Swift — SwiftLee](https://www.avanderlee.com/swift/mainactor-dispatch-main-thread/)
- [Thread dispatching and Actors — SwiftLee](https://www.avanderlee.com/concurrency/thread-dispatching-actor-execution/)
- [Structured caching in an actor — Swift Forums](https://forums.swift.org/t/structured-caching-in-an-actor/65501)
- [How the Swift compiler knows DispatchQueue.main implies @MainActor — Ole Begemann](https://oleb.net/2024/dispatchqueue-mainactor/)

---
*Architecture research for: LoRA Dataset Browser — v1.5 Performance & Live Sync*
*Researched: 2026-03-16*
