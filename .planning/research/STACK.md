# Stack Research

**Domain:** macOS performance — image/caption caching with LRU eviction, prefetch, and filesystem watchdog
**Researched:** 2026-03-16
**Confidence:** HIGH (all APIs are Apple-native, stable, and verified against official documentation and multiple implementation sources)

---

## Scope

This is a **subsequent milestone** research file for v1.5. Only stack additions needed for image caching, caption caching, prefetch, and filesystem monitoring are documented here. The existing validated base (SwiftUI + AppKit, NSViewRepresentable, MVVM, @MainActor ViewModel, security-scoped bookmarks, Task.detached image loading) is not re-litigated.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `NSCache<NSString, NSImage>` | macOS built-in | In-memory image cache with automatic memory-pressure eviction | Thread-safe, integrates with OS memory pressure system, zero dependencies. Appropriate for this use case where losing the cache is acceptable — the image is still on disk. The unpredictable eviction order is a non-issue here because all cache misses just reload from disk. |
| `CGImageSource` (ImageIO) | macOS built-in | Thumbnail generation and lazy image decoding | 4–40x faster than `NSImage(contentsOf:)` depending on format. Decodes only to the display size needed, not the full raster. Required for prefetch to be memory-efficient. Already available — ImageIO is part of Core Graphics, no new framework import needed. |
| `DispatchSource.makeFileSystemObjectSource` | macOS built-in | Directory watchdog for file additions, deletions, and external caption edits | The right tool for watching a single flat directory. FSEvents is heavier and harder to call from Swift — it targets entire hierarchies. DispatchSource VNODE + `.write` mask fires on directory-level changes (new files, deletions, renames) with no extra dependencies. |
| `DispatchSource.makeMemoryPressureSource` | macOS 10.9+ built-in | Cache eviction trigger under system memory pressure | Provides `.warning` and `.critical` events so the cache can proactively clear before NSCache's own automatic eviction fires. Supplements NSCache's built-in behavior with explicit control at known pressure points. |

### Supporting APIs

| API / Class | Framework | Purpose | When to Use |
|-------------|-----------|---------|-------------|
| `CGImageSourceCreateWithURL(_:_:)` | ImageIO | Create a lazy image source from a file URL | Use in prefetch path — creates source without decoding pixels |
| `CGImageSourceCreateThumbnailAtIndex(_:_:_:)` | ImageIO | Generate a pixel-decoded thumbnail at display size | Call with `kCGImageSourceShouldCacheImmediately: true` to force decode on the background thread during prefetch |
| `NSImage(cgImage:size:)` | AppKit | Wrap a decoded `CGImage` into an `NSImage` for the existing ZoomablePannableImage | Bridge from ImageIO path back to the NSImage the view layer expects |
| `open(path, O_EVTONLY)` | POSIX / Darwin | Open a directory file descriptor for event-only monitoring | Required argument for `makeFileSystemObjectSource`. The `O_EVTONLY` flag avoids blocking unmount of the volume. Must be closed in the cancel handler. |
| `FileManager.default.contentsOfDirectory` | Foundation | Re-scan directory after watchdog fires | Already used in `scanCurrentDirectory()` — watchdog just triggers a re-scan |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| Xcode Memory Graph Debugger | Verify NSCache releases entries under simulated memory pressure | Use Debug → Memory Graph; also use `malloc_zone_statistics` in lldb to spot leaks in the cache layer |
| Instruments → Allocations template | Profile peak RSS during prefetch | Confirm that full-resolution images are not being decoded during prefetch — only thumbnails or the final display size |

---

## Integration Points with Existing Code

### 1. Image Cache — NSCache wrapping NSImage

**Where it lives:** New `ImageCache` actor or a plain `final class` owned by `DatasetViewModel`.

**Why not a custom LRU:** NSCache's undefined eviction order is only a problem when you need to keep the newest entries and evict oldest. For this app the only consequence of eviction is a disk re-read — perfectly acceptable. A custom LRU adds ~150 lines of linked-list code and an ARC stack-overflow risk (documented: recursive deallocation of linked list nodes causes stack overflow with large caches). NSCache is sufficient and safe.

**Cost calculation:** Set `totalCostLimit` using decoded pixel bytes:
```swift
// 4 bytes per pixel (RGBA), width × height = total bytes
let cost = Int(image.size.width * image.size.height) * 4
cache.setObject(image, forKey: url.path as NSString, cost: cost)
```

**Recommended limits:**
- `countLimit`: 50 images (generous upper bound for a dataset browser)
- `totalCostLimit`: 200 MB (`200 * 1024 * 1024`) — leaves headroom for the OS on a typical 16 GB machine

**Thread safety note:** NSCache is internally thread-safe. Reads and writes from `Task.detached` background tasks are safe. However, `NSImage` is NOT thread-safe: create the NSImage on the background thread (via `CGImage` → `NSImage(cgImage:size:)`) and only pass the completed `NSImage` value back to MainActor. Never mutate an NSImage object from multiple threads. The existing `Task.detached` pattern in `ContentView.loadImageForSelection()` already does this correctly.

### 2. Prefetch — CGImageSource for display-size decode

**Pattern:** When `selectedID` changes, compute neighbors (±2 indices), launch `Task.detached` for each that is not already cached:

```swift
// In DatasetViewModel or a dedicated PrefetchCoordinator
func prefetch(around index: Int) {
    let indices = [index-2, index-1, index+1, index+2].filter { $0 >= 0 && $0 < pairs.count }
    for i in indices {
        let url = pairs[i].imageURL
        guard imageCache.object(forKey: url.path as NSString) == nil else { continue }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            let image = self.loadImageEfficiently(url: url)
            if let image {
                self.imageCache.setObject(image, forKey: url.path as NSString, cost: /* bytes */)
            }
        }
    }
}
```

**CGImageSource decode pattern for prefetch:**
```swift
func loadImageEfficiently(url: URL) -> NSImage? {
    let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return nil }
    let decodeOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,   // forces decode NOW, on this bg thread
        kCGImageSourceThumbnailMaxPixelSize: 1200     // display-size cap, not tiny thumbnail
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, decodeOptions as CFDictionary) else { return nil }
    return NSImage(cgImage: cgImage, size: .zero)    // .zero = use CGImage's pixel size
}
```

**`kCGImageSourceThumbnailMaxPixelSize` value:** 1200 px on the long edge fits a 1200×900 viewport on a 2× Retina display at 600-point logical size. Adjust to match actual view dimensions if needed, but 1200 is a safe default that avoids full-resolution decoding while still looking sharp.

**Task cancellation:** Store prefetch tasks in a `[UUID: Task<Void, Never>]` dictionary and cancel them when the user navigates to a distant image. This prevents wasted work when the user jumps quickly through the list.

### 3. Caption Cache — Dictionary in DatasetViewModel

**No third-party library needed.** Caption files are small text files (typically <4 KB). Cache them as `[URL: String]` in DatasetViewModel. The existing `pairs` array already holds caption text — the "cache" is just ensuring the text is not re-read from disk on every selection change. The current implementation already does this. The new requirement is cache invalidation when the watchdog detects an external file change.

**Invalidation on watchdog event:** When the watchdog fires for a specific caption file path, evict that entry and re-read:
```swift
func invalidateCaptionCache(for url: URL) {
    if let idx = pairs.firstIndex(where: { $0.captionURL == url }) {
        let reloaded = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        pairs[idx].captionText = reloaded
        pairs[idx].savedCaptionText = reloaded
        captionReloadToken &+= 1   // existing mechanism — tells CaptionEditingContainer to re-sync
    }
}
```

### 4. Filesystem Watchdog — DispatchSource VNODE

**What to watch:** The current `directoryURL` (flat directory only — the app shows one folder's images at a time). Watch for `.write` events on the directory itself, which fire when files are added or removed. Also watch individual caption files for `.write` events (text editor "safe save" replaces the file, which fires `.delete` + `.rename` on the parent directory — the directory `.write` mask catches this).

**Implementation skeleton:**
```swift
final class DirectoryWatchdog {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    func start(watching url: URL, onChange: @escaping () -> Void) {
        stop()
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        src.setEventHandler { onChange() }
        src.setCancelHandler { [weak self] in
            guard let self, self.fileDescriptor >= 0 else { return }
            close(self.fileDescriptor)
            self.fileDescriptor = -1
        }
        src.resume()
        source = src
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
```

**Security-scoped access:** The directory watchdog must be started only while security-scoped access is active (i.e., after `startAccessingSecurityScopedResource()` succeeds). The existing `startSecurityScopedAccess()` call in `DatasetViewModel` keeps access permanently active for the session — the watchdog can be started immediately after. No additional entitlements are required: the user already granted access via `NSOpenPanel`, and the security-scoped bookmark covers all file operations within that tree.

**Sandbox note:** `O_EVTONLY` within a security-scoped directory does not require any additional entitlements beyond what the existing bookmark provides. The flag is specifically designed for event-only monitoring and does not constitute a new file access grant.

**Re-scan after watchdog fires:** Call the existing `scanCurrentDirectory()` to rebuild `pairs`. For caption-file-only changes (external editor), do targeted invalidation via `invalidateCaptionCache(for:)` instead of a full re-scan to avoid resetting scroll position.

### 5. Memory Pressure Handler

**Pattern:** Create one `DispatchSourceMemoryPressure` at app startup (or alongside the cache) and clear the image cache on `.warning` or `.critical`:

```swift
private func installMemoryPressureHandler() {
    let source = DispatchSource.makeMemoryPressureSource(
        eventMask: [.warning, .critical],
        queue: .main
    )
    source.setEventHandler { [weak self] in
        self?.imageCache.removeAllObjects()
    }
    source.resume()
    memoryPressureSource = source   // retain it
}
```

NSCache will also auto-evict under pressure, but this explicit handler ensures the cache is cleared before the process is suspended or killed, and gives a clean slate for the re-load path.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `NSCache` | Custom LRU cache (e.g., nicklockwood/LRUCache) | Use LRUCache only if eviction order becomes a visible user-facing problem — i.e., if profiling shows the wrong images are being evicted causing repeated disk reads. For this app's single-user, sequential-navigation pattern, NSCache's undefined order is not a practical problem. |
| `CGImageSource` + `NSImage(cgImage:size:)` | `NSImage(contentsOf:)` | Keep `NSImage(contentsOf:)` only for the currently-selected image if CGImageSource integration proves complex — but note it is 4–40x slower and decodes the full resolution |
| `DispatchSource.makeFileSystemObjectSource` | FSEvents (`FSEventStreamCreate`) | Use FSEvents if recursive directory monitoring (watching subdirectories automatically) is needed. For the current flat-directory display model, DispatchSource is sufficient and far simpler to call from Swift. |
| `DispatchSource.makeMemoryPressureSource` | `NSNotification` (`UIApplication.didReceiveMemoryWarningNotification`) | `didReceiveMemoryWarning` is iOS-only. On macOS, DispatchSource memory pressure is the correct API. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Third-party image caching libraries (Kingfisher, SDWebImage) | Designed for network image loading with HTTP caching, retry logic, and CDN integration — all irrelevant for local file loading. Adds ~500 KB binary and concepts the app does not need. | `NSCache` + `CGImageSource` directly |
| FSEvents for flat-directory monitoring | Requires C-level callback bridging, runs in a separate thread requiring manual synchronization, and the recursive monitoring it provides is unnecessary for a single-directory view. | `DispatchSource.makeFileSystemObjectSource` |
| `NSImage(contentsOf:)` in the prefetch path | Decodes the full resolution image into memory. A 6000×4000 24 MP JPEG decodes to ~96 MB uncompressed. Prefetching 4 neighbors = 384 MB just for prefetch. | `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` cap |
| Mutating NSImage from a background thread | NSImage is not thread-safe. Accessing bitmap representations concurrently causes data races and sporadic crashes. | Create NSImage values on the background thread via `CGImage` → `NSImage(cgImage:size:)`, then pass completed values to MainActor. Never share a mutable NSImage across threads. |
| Setting `kCGImageSourceShouldCache: true` on the source creation options | Causes ImageIO to keep a full-resolution decoded buffer inside the CGImageSource object in addition to the thumbnail. Double memory usage for no benefit. | `kCGImageSourceShouldCache: false` on source creation, `kCGImageSourceShouldCacheImmediately: true` on thumbnail creation only |

---

## Stack Patterns by Scenario

**If the user is navigating sequentially (up/down arrows):**
- Prefetch ±2 neighbors at `.utility` priority
- Cancel prefetch tasks for indices more than 3 positions away

**If the user jumps to a distant image (clicks sidebar):**
- Cancel all in-flight prefetch tasks immediately
- Load the selected image at `.userInitiated` priority
- Start fresh prefetch from the new index

**If memory pressure `.warning` fires:**
- Call `imageCache.removeAllObjects()`
- Do NOT cancel any in-flight load for the currently selected image
- Re-prefetch will happen naturally on next navigation

**If memory pressure `.critical` fires:**
- Call `imageCache.removeAllObjects()`
- Also cancel all in-flight prefetch tasks (not the current-image task)

**If the watchdog fires a directory `.write` event:**
- Debounce 250 ms (burst writes from external tools can trigger many events per second)
- Call `scanCurrentDirectory()` to rebuild `pairs`
- Preserve `selectedID` across the rescan if the image still exists

**If the watchdog fires and only caption files changed (no new images, no deletions):**
- Call `invalidateCaptionCache(for:)` for each changed caption URL
- Skip full `scanCurrentDirectory()` to avoid resetting file list scroll position

---

## Version Compatibility

| Feature | Minimum macOS | Notes |
|---------|--------------|-------|
| `NSCache` | macOS 10.6 | Stable, long-standing API |
| `CGImageSource` / ImageIO | macOS 10.4 | Stable, no version concerns for any targeted function |
| `kCGImageSourceShouldCacheImmediately` | macOS 10.9 | Required for forcing decode on background thread |
| `DispatchSource.makeFileSystemObjectSource` | macOS 10.6 (GCD) | Stable; Swift wrapper available since Swift 3 |
| `DispatchSource.makeMemoryPressureSource` | macOS 10.9 | Stable since Mavericks |
| `NSImage(cgImage:size:)` | macOS 10.6 | Stable |
| All features combined | macOS 14+ | Project already targets macOS 14+; no compatibility concerns |

---

## Sources

- [NSCache — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/nscache) — countLimit, totalCostLimit, thread-safety guarantees; HIGH confidence
- [Fast Thumbnails with CGImageSource — macguru.dev](https://macguru.dev/fast-thumbnails-with-cgimagesource/) — benchmark data (JPEG 40x speedup vs NSImage), kCGImageSource option flags; HIGH confidence
- [kCGImageSourceShouldCacheImmediately — Apple Developer Documentation](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcacheimmediately) — forces decode at thumbnail creation time; HIGH confidence
- [DispatchSource: Detecting changes in files and folders — SwiftRocks](https://swiftrocks.com/dispatchsource-detecting-changes-in-files-and-folders-in-swift) — VNODE pattern, O_EVTONLY, event handler wiring; MEDIUM confidence
- [File and Directory Monitor in Swift — Gist/brennanMKE](https://gist.github.com/brennanMKE/55bf2975a994b518d9270cc2f3ec6716) — complete DispatchSource monitor class with state management and cancel handler; MEDIUM confidence
- [DispatchSourceMemoryPressure — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure) — .warning / .critical event mask values; HIGH confidence
- [Michael Tsai — NSCache and LRUCache (2025)](https://mjtsai.com/blog/2025/05/09/nscache-and-lrucache/) — NSCache undefined eviction order confirmed; LRU tradeoffs and ARC stack-overflow risk documented; HIGH confidence
- [NSImage is dangerous — Wade Tregaskis](https://wadetregaskis.com/nsimage-is-dangerous/) — NSImage thread-unsafety, bitmap data races, CGImage-first strategy; HIGH confidence
- [DISPATCH_SOURCE_TYPE_VNODE — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatch_source_type_vnode) — .write mask fires on directory-level changes; HIGH confidence
- [LRUCache — nicklockwood/LRUCache (GitHub)](https://github.com/nicklockwood/LRUCache) — alternative considered, rejected for this use case; MEDIUM confidence

---
*Stack research for: macOS image/caption caching, prefetch, filesystem monitoring (LoRA Dataset Browser v1.5)*
*Researched: 2026-03-16*
