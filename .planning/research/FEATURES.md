# Feature Research

**Domain:** macOS image viewer — image/caption cache with prefetch and filesystem watchdog
**Researched:** 2026-03-16
**Confidence:** HIGH (all claims grounded in Apple documentation, official APIs, or multiple independent sources)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that a "Finder-speed" image navigation experience requires. The benchmark is macOS Preview.app or Finder Quick Look: press an arrow key and the image appears instantly, with no perceptible delay.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Sub-100ms image display on arrow-key navigation | Finder and Preview load most images instantly; any visible decode delay feels broken for a daily-driver tool | MEDIUM | Current `Task.detached { NSImage(contentsOf:) }` loads cold every time; decoded NSImage objects must be cached between selections |
| LRU in-memory image cache with bounded size | Any image viewer retains recently viewed images in RAM; re-selecting a recently viewed image must be instant | MEDIUM | `NSCache` provides automatic eviction under memory pressure; for predictable LRU semantics, `LRUCache` (nicklockwood/LRUCache) is preferable — NSCache's eviction order is documented as not guaranteed |
| Prefetch of neighboring images before user navigates | Users expect the *next* and *previous* images to be ready before arrow key; delay-then-display is jarring | MEDIUM | Prefetch window of ±2 (2 ahead, 2 behind current index) covers virtually all real navigation patterns; ±1 is minimum viable |
| Caption text prefetch alongside image prefetch | When user navigates to a new image, its caption text should also be immediately available | LOW | Captions are small text files; trivial to load alongside the image in the same prefetch task |
| Memory pressure eviction of cache | App must not grow unboundedly when viewing large datasets; system memory pressure must trigger eviction | LOW | `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])` provides `.warning` and `.critical` events on macOS (unlike iOS, there is no `didReceiveMemoryWarning`); on `.warning`, evict least-recently-used half; on `.critical`, clear entirely. `NSCache` handles this automatically if used |
| Silent in-place refresh when an image is modified externally | If an external tool (e.g., an AI captioning script) overwrites the displayed image, the app should show the new version without user action | MEDIUM | Standard behavior in image-editing-adjacent tools (Pixea, Phiewer both do this); absence makes the "live sync" milestone feel incomplete |
| Silent in-place refresh when a caption .txt is modified externally | Same as above for caption files — running a batch captioning script should update the editor without the user pressing Reload | MEDIUM | Current "Reload Caption" button exists but requires manual action; the watchdog makes this automatic |
| Silent addition of new image/caption pairs to the file list | If an external process drops a new image into a watched folder, it should appear in the sidebar without re-navigating | MEDIUM | Requires re-scanning the directory list, not just refreshing one file |
| Silent removal of deleted items from the file list | If an external process deletes an image, the sidebar entry should disappear and selection should move to a neighbor | MEDIUM | Must handle the case where the currently-displayed image is deleted |

### Differentiators (Competitive Advantage)

Features that go beyond baseline expectations. For a solo developer's daily tool these matter less as "competitive advantage" and more as workflow quality-of-life improvements.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Prefetch across folder boundaries | When at the last image in a folder, preload the first image in the next folder | HIGH | Requires coordination between folder scan and cache; skip for v1.5 — within-folder prefetch is sufficient |
| Thumbnail strip in sidebar | Show decoded thumbnail next to filename for instant visual scanning | HIGH | Requires a separate thumbnail cache (much smaller resolution); significant UI change; defer to future milestone |
| Disk cache (persist decoded images to disk) | Reopening the app loads images instantly on first access, not just re-access within session | HIGH | Requires cache invalidation strategy (mtime checking), directory management, size limits; far exceeds the scope of this milestone |
| NSImage bitmap pre-decode | Forces image decompression (CGImage creation) off-main-thread during prefetch so display is truly instant | LOW | Call `image.cgImage(forProposedRect:context:hints:)` during prefetch Task to force decompression before cache insertion; small but meaningful |
| Debounced filesystem events | Coalesce rapid filesystem events (e.g., a script writing many files quickly) into a single scan instead of thrashing | LOW | Apply a 0.5s debounce timer on the watchdog callback before acting; prevents UI flicker during bulk writes |
| Dirty-state awareness for externally modified captions | If user has unsaved edits and the .txt is modified externally, warn before overwriting | MEDIUM | Show a non-modal alert or use the existing dirty indicator to block silent refresh when `editingIsDirty == true` |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Disk cache for decoded images | "Make it persist across launches" sounds like a performance win | Decoded NSImage data is device-display-format specific (resolution, color profile) and must be invalidated when the source file changes; adds significant complexity (file hashing or mtime tracking, eviction policies, disk space limits) without measurable benefit for a solo tool opening the same dataset daily | In-memory LRU cache is sufficient; macOS filesystem cache already keeps recently accessed files in RAM at the OS level |
| FSEvents (CoreServices) for directory watching | FSEvents can watch entire directory trees recursively | In a sandboxed app with security-scoped bookmarks, FSEvents is documented as "tricky" and may require disabling sandbox entitlements; DispatchSource VNODE watching is simpler, avoids sandbox complications, and is sufficient for watching a single directory | Use `DispatchSource.makeFileSystemObjectSource` with `O_EVTONLY` on the security-scoped URL's path |
| Per-file DispatchSource for every image | "Watch each image file for modifications" sounds precise | Opening O(N) file descriptors for N images in a folder is expensive; each descriptor must remain open while the source is active; for a dataset folder with 1,000+ images this leaks kernel resources | Watch only the directory-level descriptor; on a directory-write event, re-scan and diff to find which files changed |
| Preload entire dataset into RAM | "Load everything upfront for instant navigation" | A LoRA dataset can contain thousands of high-resolution images; loading all at once causes memory pressure and delays startup; the prefetch window approach provides instant navigation for all practical patterns without this cost | Prefetch ±2 neighbors; evict on LRU when cache exceeds memory budget |
| User-configurable cache size slider | "Let the user tune how much memory to use" | Adds UI complexity; the solo developer user doesn't need this; automatic memory-pressure-based eviction handles the right behavior without a preference | Use fixed budget (e.g., 200 MB total cost or 20 decoded images, whichever is hit first) with automatic eviction |
| Push notification or banner when filesystem change detected | "Tell the user something changed" | For a tool running alongside captioning scripts, constant notifications are distracting noise; the expected UX is silent refresh (like a code editor auto-reloading a file) | Refresh silently; if the current caption was dirty and overwritten externally, show one non-modal alert, then refresh |

---

## Feature Dependencies

```
[LRU Image Cache]
    └──enables──> [Prefetch of neighboring images]
                      └──requires──> [Knowing current index in pairs array] (already exists)
    └──enables──> [Instant re-display of recently viewed images]
    └──requires──> [Cache key strategy: URL.absoluteString or URL.path]

[Filesystem Watchdog (DispatchSource VNODE on directory)]
    └──enables──> [Silent refresh: modified image]
    └──enables──> [Silent refresh: modified caption]
    └──enables──> [Silent addition of new pairs to list]
    └──enables──> [Silent removal of deleted pairs from list]
    └──requires──> [Security-scoped access to the watched directory] (already active)
    └──requires──> [File descriptor opened with O_EVTONLY on the directory URL]

[Debounce timer on watchdog events]
    └──enhances──> [Filesystem Watchdog] (prevents thrash from bulk writes)

[Memory pressure handler (DispatchSource.makeMemoryPressureSource)]
    └──enhances──> [LRU Image Cache] (explicit eviction beyond what NSCache provides)

[NSImage bitmap pre-decode during prefetch]
    └──enhances──> [Prefetch of neighboring images] (forces CGImage decompression off-main-thread)

[Dirty-state guard on caption refresh]
    └──requires──> [Filesystem Watchdog — caption modified event]
    └──requires──> [vm.editingIsDirty flag] (already exists)
    └──conflicts──> [Silent caption refresh when dirty] (must warn user instead of silently overwriting)
```

### Dependency Notes

- **Cache requires index awareness:** Prefetch is keyed on the current `selectedID`'s position in `pairs`; the index is already computable from `pairs.firstIndex(where: { $0.id == selectedID })`.
- **Watchdog requires security-scoped access:** The app already keeps a long-lived security-scoped resource access (`startSecurityScopedAccess()` called once at startup). The watchdog's `open(O_EVTONLY)` call on the directory URL works within this existing scope — no new entitlement changes needed.
- **Watchdog and cache interact:** When the watchdog detects a modified image, the cache entry for that URL must be invalidated before the image is reloaded.
- **Watchdog must be torn down and rebuilt on folder navigation:** `navigateToFolder()` changes `directoryURL`; the old directory's VNODE source must be cancelled and a new one opened for the new directory.

---

## MVP Definition

### Launch With (v1.5)

Minimum set for "Finder-speed navigation with live sync."

- [ ] In-memory LRU image cache keyed by URL, bounded by size (fixed limit, e.g., 200 MB decoded or 20 images) — why essential: without this, every navigation re-decodes from disk
- [ ] Prefetch of ±2 neighbors on selection change via `Task.detached` writing into the cache — why essential: this is what makes navigation feel instant rather than fast
- [ ] Cache eviction on memory pressure via `DispatchSource.makeMemoryPressureSource` — why essential: prevents the app from growing unboundedly on large datasets
- [ ] DispatchSource VNODE watchdog on the currently-viewed directory — why essential: "live sync" milestone goal
- [ ] On directory write event: re-scan directory, diff against `pairs`, add new pairs, remove deleted pairs, invalidate cache for modified URLs — why essential: covers all three live-sync cases
- [ ] On modified image that is currently displayed: reload from disk and display — why essential: the user sees the update immediately
- [ ] On modified caption that is currently displayed and not dirty: reload caption text from disk — why essential: batch captioning scripts write captions; user expects to see them without pressing Reload
- [ ] Debounce watchdog events by 0.5s — why essential: prevents UI thrashing during bulk writes from scripted tools
- [ ] Teardown and rebuild watchdog when directory changes — why essential: without this, the wrong directory is watched after folder navigation

### Add After Validation (v1.x)

- [ ] Dirty-state guard for caption refresh (warn user before overwriting unsaved edits) — add if daily use reveals it's needed; simple once watchdog is in place
- [ ] NSImage bitmap pre-decode during prefetch — add as a micro-optimization if navigation still feels laggy after the cache is in place

### Future Consideration (v2+)

- [ ] Prefetch across folder boundaries — complex coordination; not worth the effort for solo use
- [ ] Disk cache for decoded images — high complexity, low value given OS-level filesystem caching
- [ ] Thumbnail strip in sidebar — significant UI change; separate milestone
- [ ] User-configurable cache size — not needed for solo tool

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| LRU image cache (in-memory) | HIGH | MEDIUM | P1 |
| Prefetch ±2 neighbors | HIGH | LOW (given cache exists) | P1 |
| Memory pressure eviction | HIGH | LOW | P1 |
| VNODE watchdog on directory | HIGH | MEDIUM | P1 |
| Diff + update pairs on watch event | HIGH | MEDIUM | P1 |
| Reload displayed image on modify | HIGH | LOW (given watchdog exists) | P1 |
| Reload caption on modify (when clean) | HIGH | LOW (given watchdog exists) | P1 |
| Debounce watchdog events | MEDIUM | LOW | P1 |
| Watchdog teardown on folder change | MEDIUM | LOW | P1 |
| Dirty-state guard for caption refresh | MEDIUM | LOW | P2 |
| NSImage bitmap pre-decode in prefetch | LOW | LOW | P2 |
| Thumbnail strip | LOW | HIGH | P3 |
| Disk cache | LOW | HIGH | P3 |
| User-configurable cache size | LOW | MEDIUM | Omit |

---

## UX Behavior Patterns

This section documents what "Finder-speed" and "silent sync" mean in practice, to guide implementation decisions.

### Navigation Speed Target

"Finder-speed" means: pressing an arrow key shows the next image in under 50ms perceived latency. With prefetch:
- Cache hit (prefetched neighbor): NSImage already decoded in RAM; display is a SwiftUI state update — effectively instant (<5ms)
- Cache miss (cold, no prefetch): same as today; `Task.detached { NSImage(contentsOf:) }` — 50–300ms depending on image size and disk I/O
- The prefetch window of ±2 means: for sequential navigation (the dominant pattern when reviewing datasets), the probability of a cache miss is near zero

### Prefetch Window Rationale

±2 (2 ahead, 2 behind) is the right trade-off for this use case:
- ±1 is minimum; fails when user navigates faster than one prefetch task completes
- ±2 provides a buffer for fast keyboard navigation
- ±3 or more increases memory pressure without practical benefit for sequential review
- PHCachingImageManager (Apple's own Photos framework prefetch manager) is designed around similar sliding window patterns

### Filesystem Watchdog UX

The established pattern for macOS developer tools that watch files (e.g., Pixea, code editors):

1. **Silent refresh** — no notification, no banner; the content just updates in place
2. **Current file gets priority** — if the currently displayed image or caption changes, that update happens immediately; other changes (additions, deletions) can be processed on the next debounce cycle
3. **Dirty-state exception** — if the user has unsaved caption edits and the .txt is modified externally, one non-modal alert is shown: "Caption was modified externally. Discard your changes and reload?" The alternative (silently overwriting) would cause data loss

### Watchdog Technology Choice

DispatchSource VNODE (via `DispatchSource.makeFileSystemObjectSource`) watching the directory descriptor is the right choice for this app:

- **Why not FSEvents:** FSEvents (CoreServices) is documented as "tricky" for sandboxed apps; it monitors entire directory hierarchies, which is more than needed (app only needs to watch one directory at a time); VNODE is simpler and avoids sandbox entitlement complexity
- **Why not per-file DispatchSource:** Opens O(N) file descriptors; impractical for large datasets
- **Why VNODE on directory works:** A write to any file in the directory triggers a `.write` event on the directory descriptor; the handler then re-scans and diffs

### Cache Key Strategy

Use `URL.path` (a plain `String`) as the NSCache/LRUCache key. Avoid `URL` itself as a dictionary key — URL equality includes query parameters and schemes which are irrelevant here; `path` is canonical for local files.

---

## Competitor Feature Analysis

Context: No direct competitors for this exact use case (LoRA dataset caption editor). Adjacent tools inform expectations.

| Feature | macOS Preview.app | Phiewer (Mac image viewer) | Pixea (Mac image viewer) | Our v1.5 Approach |
|---------|-------------------|---------------------------|--------------------------|-------------------|
| Arrow key navigation speed | Instant (prefetch + OS cache) | Instant (documented) | Instant | Target: instant via ±2 prefetch |
| Filesystem live refresh | No (must re-open) | Yes, auto-updates on changes | Not documented | Yes, VNODE watchdog |
| Memory management | OS-managed | App-managed | Not documented | NSCache / LRUCache with pressure eviction |
| Silent vs. notified refresh | N/A | Silent (spinner only during reindex) | N/A | Silent for images; alert only for dirty captions |

---

## Sources

- [NSCache — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/nscache)
- [NSCache — NSHipster (eviction order not guaranteed)](https://nshipster.com/nscache/)
- [LRUCache — nicklockwood/LRUCache (predictable LRU, Sendable, constant-time operations)](https://github.com/nicklockwood/LRUCache)
- [Caching and Purgeable Memory — Apple Developer Library Archive](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/ManagingMemory/Articles/CachingandPurgeableMemory.html)
- [DISPATCH_SOURCE_TYPE_VNODE — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatch_source_type_vnode)
- [DispatchSource: Detecting changes in files and folders in Swift — SwiftRocks](https://swiftrocks.com/dispatchsource-detecting-changes-in-files-and-folders-in-swift)
- [Monitoring a Folder with GCD — Cocoanetics (O_EVTONLY pattern)](https://www.cocoanetics.com/2013/08/monitoring-a-folder-with-gcd/)
- [File System Events — Apple Developer Documentation (FSEvents)](https://developer.apple.com/documentation/coreservices/file_system_events)
- [Using the FSEvents Framework — Apple Developer Library Archive](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html)
- [makeMemoryPressureSource(eventMask:queue:) — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatchsource/makememorypressuresource(eventmask:queue:))
- [Structured caching in an actor — Swift Forums](https://forums.swift.org/t/structured-caching-in-an-actor/65501)
- [Phiewer — auto-updates on filesystem changes (product documentation)](https://phiewer.com/)
- [Understanding File System Access in macOS Sandboxed Applications — CODEBIT](https://codebit-inc.com/blog/mastering-file-access-macos-sandboxed-apps/)
- [Caching in Swift — Swift by Sundell](https://www.swiftbysundell.com/articles/caching-in-swift/)

---
*Feature research for: LoRA Dataset Browser — v1.5 Performance & Live Sync*
*Researched: 2026-03-16*
