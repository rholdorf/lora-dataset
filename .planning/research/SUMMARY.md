# Project Research Summary

**Project:** LoRA Dataset Browser — v1.5 Performance & Live Sync
**Domain:** Native macOS SwiftUI/AppKit — image/caption caching with LRU eviction, neighbor prefetch, and DispatchSource filesystem watchdog
**Researched:** 2026-03-16
**Confidence:** HIGH

## Executive Summary

The v1.5 milestone adds two orthogonal capabilities to an already-working app: (1) Finder-speed image navigation via an in-memory LRU cache and background prefetch of neighboring images, and (2) live sync — silent, automatic refresh when external tools modify or add files in the watched directory. Both features are well-understood on macOS and map cleanly to native Apple APIs with no third-party dependencies required. The implementation is evolutionary, not architectural: two new Swift files (`ImageCache.swift` as a Swift `actor`, `FilesystemWatchdog.swift` as a plain class) plus targeted changes to `DatasetViewModel` and `ContentView`.

The recommended stack is 100% Apple-native. `NSCache<NSURL, NSImage>` handles the LRU image cache with automatic memory-pressure eviction. `CGImageSource` (ImageIO framework, already linked) provides 4–40x faster image decoding than `NSImage(contentsOf:)` by decoding only to display size rather than full resolution. `DispatchSource.makeFileSystemObjectSource` with `O_EVTONLY` watches the current directory for structural changes (additions, deletions, renames) while a second source watches the currently selected caption file for content changes — total: two file descriptors, never O(N). All threading bridges from GCD callbacks back to `@MainActor` via `Task { @MainActor in }`, which is the established pattern for Swift Concurrency + GCD interop.

The primary risks are a cluster of known pitfalls around threading and lifecycle: opening the watchdog file descriptor before security-scoped access is active (silent failure), using file size instead of decoded pixel bytes as NSCache cost (silent memory bloat), ignoring the self-write echo that causes a save to immediately trigger a reload, and failing to cancel stale prefetch tasks when the user navigates quickly. Every one of these pitfalls has a specific, one-to-five-line fix. None require architectural rework if caught at design time.

---

## Key Findings

### Recommended Stack

All required capabilities are served by APIs that already exist on the macOS 14+ target. No new frameworks or package dependencies are needed.

**Core technologies:**

- `NSCache<NSURL, NSImage>`: in-memory image cache — thread-safe, OS memory-pressure-aware, zero dependencies; eviction order is undefined but that is acceptable because a cache miss simply re-reads from disk
- `CGImageSource` / ImageIO (`CGImageSourceCreateThumbnailAtIndex` + `kCGImageSourceShouldCacheImmediately`): background image decoding at display size — 4–40x faster than `NSImage(contentsOf:)` for compressed formats; forces full pixel decode on the background thread during prefetch so display is instantaneous on cache hit
- `DispatchSource.makeFileSystemObjectSource` with `O_EVTONLY`: directory-level and file-level filesystem event delivery — simpler than FSEvents, no sandbox complications, correct for a flat single-directory view
- `DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical])`: explicit cache eviction under system memory pressure beyond what NSCache's automatic behavior provides; macOS-only (iOS uses `didReceiveMemoryWarning`)

**Critical configuration:**

- NSCache cost must be `Int(image.size.width * image.size.height) * 4` (decoded RGBA bytes), never file size on disk
- NSCache limits: `countLimit = 50`, `totalCostLimit = 200 MB` (or 15% of physical RAM for adaptive sizing)
- Prefetch window: ±2 neighbors at `.utility` / `.background` priority; tasks stored by UUID and cancelled when the window shifts

### Expected Features

**Must have (table stakes for v1.5):**

- Sub-50ms perceived image display on arrow-key navigation — current cold-load path (50–300ms) is noticeable; cache hit path is <5ms
- In-memory LRU image cache keyed by `URL.path`, bounded by decoded byte cost
- Prefetch of ±2 neighboring images on selection change
- Memory pressure eviction via `DispatchSource.makeMemoryPressureSource`
- DispatchSource VNODE watchdog on the current directory — structural changes (adds, deletions, renames)
- Single file-level VNODE watcher on the selected caption file — content changes from external editors
- Directory rescan and pairs diff on watchdog event; add new pairs, remove deleted pairs, preserve selection if image still exists
- Silent caption reload when external change detected and caption is not dirty
- 0.5s debounce on watchdog events to prevent UI thrashing from bulk writes
- Watchdog teardown and rebuild on directory navigation

**Should have (v1.x, after validation):**

- Dirty-state guard for caption reload: if `editingIsDirty == true` when a watchdog event arrives for the selected caption file, show a non-blocking "Caption changed externally. Reload?" banner instead of silently discarding edits — this is data loss prevention
- NSImage bitmap pre-decode during prefetch (call `image.cgImage(forProposedRect:context:hints:)` to force decompression off main thread before cache insertion) — micro-optimization, add only if profiling shows residual lag after cache is in place

**Defer to v2+:**

- Disk cache for decoded images — high complexity (mtime invalidation, eviction policies, disk space limits), low value given OS-level filesystem caching
- Thumbnail strip in sidebar — separate milestone, requires a second cache at thumbnail resolution
- Cross-folder prefetch — complex coordination, not worth the effort for solo use
- User-configurable cache size slider — not needed; automatic pressure-based eviction handles the right behavior

### Architecture Approach

The v1.5 architecture adds two standalone components owned by `DatasetViewModel`. `ImageCache` is a Swift `actor` — compiler-enforced isolation ensures the combined cache-lookup + in-flight-task-deduplication check is atomic without explicit locking. `FilesystemWatchdog` is a plain `final class` (not an actor) because GCD's `DispatchSource` requires a concrete `DispatchQueue`, not a Swift actor executor. The watchdog bridges back to `@MainActor` via `Task { @MainActor in vm.handleFSEvent() }` from within the GCD handler. Loading image data for display moves from `ContentView` into `DatasetViewModel.loadImage(for:)`, which delegates to the cache actor — a minor surface change on `ContentView` that correctly relocates I/O responsibility.

**Major components:**

1. `actor ImageCache` (new file) — NSCache wrapper with `[URL: Task<NSImage?, Never>]` in-flight deduplication; prefetch API writes neighbors at background priority; evict API cancels in-flight tasks
2. `class FilesystemWatchdog` (new file) — two DispatchSource instances (directory-level + selected-file-level); delivers typed events to ViewModel via async closure callbacks; owns and closes its file descriptors via cancel handlers
3. `DatasetViewModel` (modified) — owns both components; triggers `prefetch(around: selectedIndex)` in `selectedID.didSet`; handles FS events on `@MainActor`; suppresses self-write echoes by stopping the file watcher before save and restarting after
4. `ContentView` (minor modification) — `loadImageForSelection()` calls `await vm.loadImage(for: pair)` instead of directly spawning a detached task with `NSImage(contentsOf:)`

**Build order:** `ImageCache` → `FilesystemWatchdog` → `DatasetViewModel` → `ContentView`. Steps 1 and 2 have no cross-dependency and can be written in parallel.

### Critical Pitfalls

**v1.5 — Cache and Watchdog (primary concern for this milestone):**

1. **NSCache cost must use decoded pixel bytes, not file size** — a 4000×3000 PNG is 48 MB decoded vs 3 MB on disk; wrong cost causes silent memory bloat and eventual app jettison; fix: `cost = Int(image.size.width * image.size.height) * 4`

2. **Watchdog file descriptor must open after `startAccessingSecurityScopedResource()` succeeds** — `open(O_EVTONLY)` on a sandbox-protected path returns -1 before access is granted; symptom: watchdog silently never fires on session restore; fix: initialize watchdog at the end of `chooseDirectory()` and `restorePreviousDirectoryIfAvailable()`, after access is confirmed active

3. **App's own caption save triggers a self-write echo on the watchdog** — causes immediate reload after save, potentially discarding dirty state; fix: `watchdog.stopFile()` before write, `defer { watchdog.watchFile(...) }`; alternatively, suppress events whose file mod date falls within 2 seconds of the last save timestamp

4. **Stale prefetch task delivers the wrong image after rapid navigation** — `Task.detached` without explicit cancellation continues loading after the user has moved on; fix: store the load task in `loadTask: Task<Void, Never>?`, cancel before starting a new one, check `Task.isCancelled` inside the task body before the `MainActor.run` dispatch

5. **Dirty caption conflict on external change** — watchdog reload unconditionally overwrites user's in-progress edits; fix: gate on `editingIsDirty`; if dirty, update `savedCaptionText` only and surface a "Caption changed externally. Reload?" banner; never silently discard unsaved text

6. **DispatchSource VNODE requires one open fd per watched file** — watching all N image and caption files would exhaust the per-process fd limit (~256 default soft limit) at 257+ files; fix: watch only the directory descriptor (one fd) for structural events, and the currently selected caption file (one fd) for content events; maximum 2 descriptors total at any time

7. **`@MainActor` isolation violation from GCD handler** — accessing `vm.pairs` or `vm.editingIsDirty` directly in the DispatchSource event handler is a data race (Swift 6 compile error; TSan hit in Swift 5.x); fix: all ViewModel access goes through `Task { @MainActor in vm.method() }` inside the handler

**Earlier milestones (v1.4 context, relevant to existing code):**

- QLPreviewPanel + NSTextView focus conflict: NSTextView's private responder method claims the panel before the custom controller; fix: `window?.makeFirstResponder(nil)` before opening the panel
- NSTextView `updateNSView` cursor reset: unconditional `nsView.string = binding` on every SwiftUI update causes cursor-jump; fix: guard with `nsView.string != text` and `!coordinator.isEditing`

---

## Implications for Roadmap

Based on the dependency graph in FEATURES.md and the build order in ARCHITECTURE.md, the natural phase structure for v1.5 is three focused phases. Each phase can be validated independently before the next begins.

### Phase 1: Image Cache + Prefetch

**Rationale:** The cache is a pure addition with no dependency on the watchdog. It can be implemented and tested in isolation. It delivers the most user-visible improvement (Finder-speed navigation) with the least integration risk. Building it first establishes the `actor ImageCache` threading pattern that the watchdog phase mirrors.

**Delivers:** Instant navigation for sequential dataset review; bounded memory usage regardless of dataset size.

**Features from FEATURES.md:** In-memory LRU image cache keyed by URL.path; prefetch ±2 neighbors on selection change; memory pressure eviction via `DispatchSource.makeMemoryPressureSource`; optional NSImage bitmap pre-decode.

**Implements:** `ImageCache.swift` (new actor), `DatasetViewModel.triggerPrefetch()` (new method), `ContentView.loadImageForSelection()` (minor modification to delegate to cache).

**Pitfalls to address in this phase:** Decoded-byte cost calculation (Pitfall 11 in PITFALLS.md); stale prefetch task cancellation (Pitfall 9); NSImage thread-safety — create via CGImage path on background thread, pass completed value to MainActor.

**Research flag:** Standard patterns, well-documented. Architecture document provides compilable code. No phase-level research needed.

### Phase 2: Filesystem Watchdog — Structural Changes

**Rationale:** The watchdog depends on security-scoped access being active (already established in the codebase) and on `scanCurrentDirectory()` existing (it does). Structural monitoring — directory-level adds, deletions, renames — is the simpler half: one DispatchSource on the directory fd, triggering the existing rescan. Implementing it first validates the GCD→@MainActor bridge pattern in isolation before adding the more nuanced caption-file-level watcher.

**Delivers:** Silent addition of new image/caption pairs when external tools drop files in the folder; silent removal of deleted pairs; selection preserved across rescan.

**Features from FEATURES.md:** VNODE watchdog on current directory; directory rescan and pairs diff on event; debounce (0.5s); watchdog teardown and rebuild on folder navigation.

**Implements:** `FilesystemWatchdog.swift` (new class, directory-level source only for this phase), `DatasetViewModel` `handleFSEvent()` and updates to `navigateToFolder()` / `chooseDirectory()`.

**Pitfalls to address in this phase:** Security-scoped access sequencing — initialize watchdog only after access confirmed (Pitfall 7); `@MainActor` isolation from GCD handler — all ViewModel access via `Task { @MainActor in }` (Pitfall 12); fd exhaustion — one directory descriptor only (Pitfall 6); watchdog teardown must happen before `directoryURL` update, not after.

**Research flag:** Standard patterns. Architecture document provides a compilable `FilesystemWatchdog` skeleton. No additional research needed.

### Phase 3: Filesystem Watchdog — Caption Content Changes

**Rationale:** Caption content monitoring (file-level watcher on the selected caption file) introduces two additional complexities not present in Phase 2: self-write echo suppression and the dirty-caption conflict. Separating it allows Phase 2 to be validated cleanly first, and the self-write suppression touches `saveSelected()` which is the most sensitive mutation path in the app.

**Delivers:** Automatic caption reload when an external tool (training script, text editor) rewrites the active caption file; dirty-state guard prevents silent data loss.

**Features from FEATURES.md:** Silent caption reload when external change detected and caption not dirty; "Caption changed externally. Reload?" banner when caption has unsaved edits.

**Implements:** `FilesystemWatchdog.watchFile(_:)` and `stopFile()` (additions to Phase 2 class), `DatasetViewModel.watchSelectedCaptionFile()` and `reloadCaptionForSelected()` (new/updated methods), `saveSelected()` self-write suppression.

**Pitfalls to address in this phase:** Self-write echo (Pitfall 8) — stop file watcher before save, restart after via `defer`; dirty caption conflict (Pitfall 10) — gate on `editingIsDirty`, never silently discard edits; `@MainActor` isolation (Pitfall 12, same fix as Phase 2).

**Research flag:** The UX decision for the dirty-caption conflict (banner style, button labels, whether to auto-dismiss) should be made explicit in the phase requirements before coding begins. FEATURES.md documents the established pattern ("one non-modal alert, then refresh if user confirms"). No additional research needed — the decision is a product choice, not a technical unknown.

### Phase Ordering Rationale

- Phase 1 before Phase 2: cache is independent of the watchdog, delivers the most visible value immediately, and the actor pattern established here informs watchdog threading design
- Phase 2 before Phase 3: the directory-level VNODE source validates the GCD bridge before adding caption-specific logic; `FilesystemWatchdog` class exists and is tested before file-level sources are added to it
- Phase 3 last: depends on Phase 2's class being stable, and the self-write suppression in `saveSelected()` is safer to add when the watchdog infrastructure is already verified

### Research Flags

**No phases require `/gsd:research-phase` during planning.** All three phases are covered by official Apple documentation and verified community sources. The architecture document provides compilable code for all major components.

**Implementation-time decisions to make explicit in phase requirements (not requiring research, but requiring deliberate choice before coding):**

- Phase 1: adaptive cache sizing (`0.15 * physicalMemory`) vs. fixed 200 MB limit — pick one and document it in requirements
- Phase 1: whether to use the CGImageSource thumbnail decode path or keep `NSImage(contentsOf:)` with the cache — simpler without CGImageSource; add it only if profiling shows residual decode time after the cache is in place
- Phase 3: exact UX for the dirty-caption conflict banner (style, button labels, dismiss behavior)

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All APIs are Apple-native, stable, verified against official documentation and multiple independent sources. No third-party dependencies. Version compatibility confirmed for macOS 14+ target. |
| Features | HIGH | Feature set grounded in Apple documentation and adjacent tool analysis (Preview.app, Phiewer, Pixea). Anti-features are well-reasoned with documented alternatives. MVP scope is conservative. |
| Architecture | HIGH (cache + threading model) / MEDIUM (watchdog event semantics) | Cache placement, actor isolation, and GCD bridge patterns are well-documented and compiler-enforced. DispatchSource `.write` directory semantics — fires on adds/deletes/renames but NOT file content changes — required community source verification because Apple's official docs are JavaScript-gated. |
| Pitfalls | HIGH | 12 specific pitfalls documented with concrete fixes. All critical ones (cost calculation, security-scoped sequencing, self-write echo, stale task cancellation, dirty-caption conflict, fd exhaustion, @MainActor isolation) are confirmed by multiple sources and have fixes ranging from one line to five lines. |

**Overall confidence:** HIGH

### Gaps to Address

- **DispatchSource directory `.write` event semantics need early empirical validation:** The ARCHITECTURE.md notes that `DISPATCH_SOURCE_TYPE_VNODE` documentation required JavaScript to render and was verified via community sources (SwiftRocks, Cocoanetics). As the first action in Phase 2, implement and test the directory watcher against a real test directory to confirm the `.write` event mask fires on file addition and deletion as documented, before building any dependent logic on that assumption.

- **NSCache eviction timing on macOS 14+ is implementation-defined:** The `DispatchSource.makeMemoryPressureSource` explicit handler supplements NSCache's built-in behavior, but the exact timing of NSCache's automatic eviction is not testable without simulated memory pressure. Use Instruments → Allocations during Phase 1 review to confirm the cache respects `totalCostLimit` in real usage.

- **macOS 15.0 Sequoia security-scoped bookmarks regression:** PITFALLS.md documents a bug in macOS 15.0 where bookmarks incorrectly return `isStale == true`, fixed in 15.1. The current environment runs macOS 25.3.0 (Darwin 25.x, macOS 16.x era), so this specific regression is not active. However, `isStale` handling should be verified during Phase 2 when watchdog initialization touches bookmark resolution — confirm the existing graceful fallback to the folder picker is in place.

---

## Sources

### Primary (HIGH confidence)

- [NSCache — Apple Developer Documentation](https://developer.apple.com/documentation/foundation/nscache) — countLimit, totalCostLimit, thread-safety guarantees
- [kCGImageSourceShouldCacheImmediately — Apple Developer Documentation](https://developer.apple.com/documentation/imageio/kcgimagesourceshouldcacheimmediately) — forces decode at thumbnail creation time on background thread
- [DispatchSourceMemoryPressure — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure) — .warning / .critical event masks
- [DISPATCH_SOURCE_TYPE_VNODE — Apple Developer Documentation](https://developer.apple.com/documentation/dispatch/dispatch_source_type_vnode) — .write mask on directory descriptor
- [NSImage is dangerous — Wade Tregaskis](https://wadetregaskis.com/nsimage-is-dangerous/) — NSImage thread-unsafety, bitmap data races, CGImage-first strategy
- [Michael Tsai — NSCache and LRUCache (2025)](https://mjtsai.com/blog/2025/05/09/nscache-and-lrucache/) — NSCache undefined eviction order confirmed; LRU tradeoffs and ARC stack-overflow risk
- [Apple Developer Forums: Finder Sync Extension does not allow for sandboxed access](https://developer.apple.com/forums/thread/717098) — security-scoped bookmarks not crossing process boundary (Apple staff confirmed)
- [Apple Developer Forums: How do I update state in NSViewRepresentable](https://developer.apple.com/forums/thread/125920) — updateNSView cursor/state pitfalls
- [Enabling Selection, Double-Click and Context Menus in SwiftUI List Rows on macOS — SerialCoder.dev](https://serialcoder.dev/text-tutorials/swiftui/enabling-selection-double-click-and-context-menus-in-swiftui-list-on-macos/) — contextMenu(forSelectionType:) selection behavior

### Secondary (MEDIUM confidence)

- [Fast Thumbnails with CGImageSource — macguru.dev](https://macguru.dev/fast-thumbnails-with-cgimagesource/) — benchmark data (JPEG 40x speedup vs NSImage), kCGImageSource option flags
- [DispatchSource: Detecting changes in files and folders — SwiftRocks](https://swiftrocks.com/dispatchsource-detecting-changes-in-files-and-folders-in-swift) — VNODE pattern, O_EVTONLY, event handler wiring
- [File and Directory Monitor in Swift — Gist/brennanMKE](https://gist.github.com/brennanMKE/55bf2975a994b518d9270cc2f3ec6716) — complete DispatchSource monitor class with state management and cancel handler
- [QuickLook + TextView Trouble — Michael Berk](https://mberk.com/posts/QuickLook+TextViewTrouble/) — NSTextView / QLPreviewPanel responder chain conflict
- [MacEditorTextView gist — unnamedd](https://gist.github.com/unnamedd/6e8c3fbc806b8deb60fa65d6b9affab0) — NSTextView NSViewRepresentable reference implementation with isEditing guard
- [How the Swift compiler knows DispatchQueue.main implies @MainActor — Ole Begemann](https://oleb.net/2024/dispatchqueue-mainactor/) — GCD to @MainActor bridge correctness
- [Structured caching in an actor — Swift Forums](https://forums.swift.org/t/structured-caching-in-an-actor/65501) — actor-isolated cache pattern with in-flight deduplication

---
*Research completed: 2026-03-16*
*Ready for roadmap: yes*
