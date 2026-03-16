# Phase 11: Filesystem Watchdog -- Structural Changes - Research

**Researched:** 2026-03-16
**Domain:** macOS filesystem event monitoring (DispatchSource VNODE), debounce patterns, directory tree watching
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Selection behavior on deletion:**
- When the selected image is deleted externally, jump to the next neighbor in the sorted list (or previous if it was the last item)
- If the selected image's caption file is deleted but the image remains, clear the caption editor and treat as a new image (saving would create a new .txt file)
- When all images are deleted, show empty sidebar + blank detail pane (same as opening an empty folder today, no special message)
- If user has unsaved caption edits and the corresponding image is deleted externally, silently discard edits and move to next neighbor -- no prompt or toast

**New file appearance:**
- Silent sorted insertion -- new files slot into alphabetical position with no animation or highlight
- Preserve scroll position and current selection when the file list updates
- Auto-pair by basename -- same pairing logic as scanCurrentDirectory (match image.png with image.txt)
- Renames treated as delete + add -- no rename tracking. DispatchSource doesn't distinguish renames anyway

**Folder tree updates:**
- Watch folder tree too -- new subfolders appear and deleted subfolders disappear live
- If the currently-viewed folder is deleted externally, navigate to its parent folder
- Preserve folder expansion state (expandedPaths) across tree rebuilds
- If currently-viewed folder's parent is also deleted, walk up to the nearest surviving ancestor (or root)

**Cache interaction:**
- Prefetch new files only if they land within the ±2 window of current selection
- Evict cache entries immediately when files are deleted (don't wait for LRU)
- Cancel in-flight prefetch tasks for deleted files
- Invalidate cache entries when an image file is replaced externally (same filename, different content)
- After rescan settles, re-trigger prefetch around current selection (±2 neighbors may have shifted)

### Claude's Discretion
- Debounce architecture (single timer for both file list and folder tree, or separate timers)
- Watcher technology choice (DispatchSource VNODE, FSEvents, or combination)
- Rescan implementation (full rescan vs incremental diff)
- Debug logging strategy for watchdog events

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| WATCH-01 | Directory-level VNODE watcher detects file additions, deletions, and renames | DispatchSource.makeFileSystemObjectSource with eventMask: .write on the directory fd fires on any structural change; rename = delete + add so .write covers it |
| WATCH-02 | File list updates silently when files are added or removed externally | Debounced rescan calls existing scanCurrentDirectory(); UI updates via @Published pairs on MainActor |
| WATCH-03 | Watchdog events are debounced (0.5s) to prevent UI thrashing | DispatchWorkItem cancel-and-reschedule pattern on a background queue, dispatching to MainActor after delay |
| WATCH-04 | Watchdog tears down and rebuilds when navigating to a different folder | stop() cancels DispatchSource and closes fd; start() opens new fd for new directory; called from navigateToFolder() and chooseDirectory() |
</phase_requirements>

---

## Summary

Phase 11 introduces a filesystem watchdog that keeps the sidebar file list and folder tree accurate when external tools add or delete files in the watched folder. The implementation is built exclusively on Apple's `DispatchSource` VNODE mechanism -- no third-party libraries required.

The core data flow is: DispatchSource fires a `.write` event on the watched directory fd whenever any structural change occurs (add, delete, rename). A debounce timer (0.5 s, using `DispatchWorkItem`) absorbs bursts of events (e.g., copying 50 files). When the debounce settles, a rescan executes on MainActor via the existing `scanCurrentDirectory()`. After rescan, diff logic handles cache eviction and prefetch re-triggering.

**Primary recommendation:** Use a single `DirectoryWatcher` class per watched URL (one for the image directory, one for the root directory tree). Each watcher opens the directory with `O_EVTONLY`, creates a `DispatchSourceFileSystemObject` with `.write` mask, and invokes a callback on the provided queue. `DatasetViewModel` holds watcher instances and replaces them on folder navigation.

The security-scoped access that is already active for the directory (via `startSecurityScopedAccess()`) covers `open()` O_EVTONLY calls on subdirectories within the security scope. The existing `isAccessingSecurityScope` guard must be active before the watcher is started.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `Dispatch` (GCD) | Built-in (macOS 10.10+) | DispatchSource VNODE file system event source | Built into Foundation; zero dependencies; deterministic teardown |
| `Foundation` | Built-in | `FileManager`, `URL`, `DispatchWorkItem` | Already used throughout the project |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `Darwin.POSIX` (open/close) | Built-in | Low-level fd management for DispatchSource | Required -- DispatchSource takes a raw `CInt` fd, not a FileHandle |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| DispatchSource VNODE | FSEvents API | FSEvents watches recursive trees and is better for deep hierarchies; but adds C-bridging complexity and is overkill for single-directory watching. DispatchSource is simpler for the two flat watchers this phase needs. |
| DispatchSource VNODE | `NSWorkspace.shared.notificationCenter` fileSystemChange | Not a real notification API for arbitrary directories; doesn't exist for this use case. |
| DispatchWorkItem debounce | Combine `debounce` operator | Combine works but requires importing Combine and passing `AnyPublisher` plumbing; DispatchWorkItem is self-contained. |

**Installation:** No additional packages. All APIs are part of macOS SDK.

## Architecture Patterns

### Recommended Project Structure
```
lora-dataset/
├── DatasetViewModel.swift      # holds watchers, calls rescan, diff logic
├── DirectoryWatcher.swift      # NEW: thin DispatchSource wrapper
├── ImageCacheActor.swift       # add remove(for:) for targeted eviction
└── lora-datasetTests/
    └── DirectoryWatcherTests.swift  # NEW: unit tests for watcher lifecycle
```

### Pattern 1: DirectoryWatcher -- DispatchSource VNODE Wrapper

**What:** A class that encapsulates one DispatchSource VNODE on a single directory URL. Calls a callback on a specified `DispatchQueue` whenever a `.write` event fires.

**When to use:** One instance per watched directory (content directory and root directory get separate watchers).

**Example:**
```swift
// Source: Apple Developer Documentation - DISPATCH_SOURCE_TYPE_VNODE
// Source: Apple DirectoryMonitor sample (ListerKit)

final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let url: URL
    private let onChange: () -> Void
    private let queue: DispatchQueue

    init(url: URL, queue: DispatchQueue, onChange: @escaping () -> Void) {
        self.url = url
        self.queue = queue
        self.onChange = onChange
    }

    func start() {
        guard source == nil else { return }
        // O_EVTONLY: event-only fd; does not prevent unmount
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            print("[watchdog] failed to open fd for \(url.lastPathComponent)")
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )
        src.setEventHandler { [weak self] in
            self?.onChange()
        }
        src.setCancelHandler {
            close(fd)  // MUST close fd in cancel handler
        }
        src.resume()
        source = src
        print("[watchdog] started watching \(url.lastPathComponent)")
    }

    func stop() {
        source?.cancel()
        source = nil
        print("[watchdog] stopped watching")
    }

    deinit { stop() }
}
```

### Pattern 2: Debounce with DispatchWorkItem

**What:** Cancel-and-reschedule pattern. Every raw watchdog event cancels the previous pending work item and schedules a fresh one. Only the last event in a burst executes.

**When to use:** In the DispatchSource event handler, before calling back to the ViewModel.

**Example:**
```swift
// Source: DispatchWorkItem debounce pattern (Natan Rolnik, onmyway133)
// Implemented inside DatasetViewModel or a helper

private var debounceWorkItem: DispatchWorkItem?
private let debounceDelay: TimeInterval = 0.5

private func scheduleRescan() {
    debounceWorkItem?.cancel()
    let item = DispatchWorkItem { [weak self] in
        Task { @MainActor [weak self] in
            self?.performRescan()
        }
    }
    debounceWorkItem = item
    DispatchQueue.global(qos: .utility).asyncAfter(
        deadline: .now() + debounceDelay,
        execute: item
    )
}
```

### Pattern 3: Watchdog Lifecycle in DatasetViewModel

**What:** The ViewModel holds two `DirectoryWatcher` instances: one for the currently-viewed image directory and one for the root directory (folder tree). Both share the same debounce work item via a unified callback.

**When to use:** Replace watchers whenever the directory changes (navigateToFolder, chooseDirectory).

**Example:**
```swift
// Inside DatasetViewModel
private var contentWatcher: DirectoryWatcher?
private var treeWatcher: DirectoryWatcher?

private func startWatching(_ contentURL: URL, rootURL: URL) {
    stopWatching()
    let q = DispatchQueue(label: "com.loradataset.watchdog", qos: .utility)
    contentWatcher = DirectoryWatcher(url: contentURL, queue: q) { [weak self] in
        self?.scheduleRescan(kind: .content)
    }
    treeWatcher = DirectoryWatcher(url: rootURL, queue: q) { [weak self] in
        self?.scheduleRescan(kind: .tree)
    }
    contentWatcher?.start()
    treeWatcher?.start()
}

private func stopWatching() {
    contentWatcher?.stop()
    contentWatcher = nil
    treeWatcher?.stop()
    treeWatcher = nil
    debounceWorkItem?.cancel()
    debounceWorkItem = nil
}
```

### Pattern 4: Post-Rescan Diff and Cache Eviction

**What:** After `scanCurrentDirectory()` runs and produces a new `pairs` array, diff against the previous set to find added and removed image URLs. Evict removed entries from cache immediately; schedule prefetch for any additions within the ±2 window.

**When to use:** Inside `performRescan()` after updating `self.pairs`.

**Example:**
```swift
// Source: project conventions (ImageCacheActor.swift, DatasetViewModel.swift)
private func performRescan() {
    let oldURLs = Set(pairs.map(\.imageURL))
    scanCurrentDirectory()  // updates self.pairs
    let newURLs = Set(pairs.map(\.imageURL))

    let removed = oldURLs.subtracting(newURLs)
    let added = newURLs.subtracting(oldURLs)

    // Evict immediately
    for url in removed {
        Task { await imageCache.remove(for: url) }
        prefetchTasks[url]?.cancel()
        prefetchTasks.removeValue(forKey: url)
    }

    // Selection repair (see Locked Decisions)
    if let sid = selectedID, removed.contains(pairs.first(where: { $0.id == sid })?.imageURL ?? URL(fileURLWithPath: "")) {
        // advance to next neighbor
        repairSelectionAfterDeletion(removedURL: ...)
    }

    // Re-trigger prefetch around settled selection
    if let id = selectedID {
        triggerPrefetch(aroundID: id)
    }

    print("[watchdog] rescan: +\(added.count) -\(removed.count)")
}
```

### Anti-Patterns to Avoid

- **Not calling `stop()` before starting a new watcher:** The old `DispatchSource` holds an open file descriptor and fires stale events on the old directory path. Always call `stopWatching()` in `navigateToFolder()` and `chooseDirectory()` before calling `startWatching()`.
- **Cancelling the DispatchSource without a cancel handler that closes the fd:** Leads to file descriptor leak. The cancel handler calling `close(fd)` is mandatory.
- **Dispatching UI updates directly from the DispatchSource queue:** The watcher fires on a utility queue. UI state (`pairs`, `folderTree`, `selectedID`) must be updated on MainActor. Use `Task { @MainActor in ... }`.
- **Using FileHandle instead of `open()` for the fd:** `FileHandle(forReadingFrom:)` works but the DispatchSource `.delete` event can invalidate the fd while FileHandle still has a reference. Using raw `open()` + close in cancel handler is the canonical pattern.
- **Sharing one DispatchWorkItem variable across multiple queues without synchronization:** The debounce work item is only ever touched from a single serial utility queue, so no lock is needed. Do not touch it from MainActor without re-dispatching.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Detecting directory structural changes | Custom kqueue / NSStream polling | `DispatchSource.makeFileSystemObjectSource` with `.write` | Built-in; handles add/delete/rename uniformly; O_EVTONLY prevents preventing unmount |
| Debouncing rapid events | Custom `Timer`-based debounce class | `DispatchWorkItem` cancel + asyncAfter | Simpler, no Timer lifecycle management, already used in project |
| Absorbing bulk copies | Custom event coalescing queue | 0.5 s `DispatchWorkItem` debounce | DispatchSource itself coalesces rapid kernel events into fewer callbacks; 0.5 s debounce handles user-visible bursts |
| Cache eviction for deleted files | Re-running full LRU eviction | `imageCache.remove(for: url)` (new targeted method) | Immediate eviction is correct; LRU eviction would only eventually remove deleted entries |

**Key insight:** DispatchSource already coalesces multiple rapid kernel events (e.g., 50 files written at once) into a single handler invocation in many cases. The 0.5 s debounce is the safety net for the cases where multiple events do fire -- it ensures only one rescan executes per burst.

## Common Pitfalls

### Pitfall 1: Security-Scoped Access Not Active When Opening fd

**What goes wrong:** `open(url.path, O_EVTONLY)` returns `-1` (EPERM or ENOENT) because the sandbox hasn't granted access to the directory.

**Why it happens:** The app's security-scoped access from `startAccessingSecurityScopedResource()` must be active before calling `open()`. If `startWatching()` is called before the security scope is started (e.g., in init before bookmark resolution), the open fails.

**How to avoid:** Only call `startWatching()` after `startSecurityScopedAccess()` has been called. In the existing code flow, this means calling `startWatching()` at the end of `chooseDirectory()` and `restorePreviousDirectoryIfAvailable()`, after `isAccessingSecurityScope = true`. Check the return value of `open()` and log `[watchdog] failed to open fd` if it's -1.

**Warning signs:** `[watchdog] failed to open fd` in console; file list never updates on external changes.

### Pitfall 2: Watcher Fires on Its Own Rescan

**What goes wrong:** `scanCurrentDirectory()` reads the directory, which on some macOS versions triggers a `.write` event on the watched directory fd, causing an infinite rescan loop.

**Why it happens:** On certain FS implementations, reading directory contents (via `contentsOfDirectory`) can bump the directory's mtime/generation count.

**How to avoid:** The 0.5 s debounce absorbs a single bounce-back because the rescan completes before the debounce timer re-fires. However, add a guard (`isRescanning` flag) inside `performRescan()` to prevent re-entrant rescans.

**Warning signs:** Console shows `[watchdog] rescan: +0 -0` repeating every 0.5 s with no user action.

### Pitfall 3: Watcher Fires After Stop (Race Condition)

**What goes wrong:** `stop()` is called (e.g., on folder navigation), but a queued event handler still fires after `source?.cancel()` returns.

**Why it happens:** `cancel()` is asynchronous -- the cancel handler runs after all queued event handlers. An event already on the queue when `stop()` is called may still execute.

**How to avoid:** The `onChange` callback uses `[weak self]`, so if the watcher is replaced and the old one deallocated, the callback is a no-op. Additionally, the debounce `DispatchWorkItem` is cancelled in `stopWatching()`, so even if the old callback fires, its scheduled rescan is cancelled before it runs.

**Warning signs:** `[watchdog] rescan` fires after folder navigation, potentially rescanning the old directory.

### Pitfall 4: Deleted Watched Directory -- Watcher Becomes Stale

**What goes wrong:** The currently-watched directory is deleted externally. The DispatchSource fires a `.write` event (or `.delete` event). After that, `scanCurrentDirectory()` fails because the directory no longer exists.

**Why it happens:** VNODE `.write` covers structural changes but once the directory vnode is gone, the fd is no longer valid.

**How to avoid:** In `performRescan()`, check if `directoryURL` still exists after rescan. If `FileManager.default.fileExists(atPath: directoryURL.path)` is false, call `navigateToParent()` which walks up to the nearest surviving ancestor using `directoryURL.deletingLastPathComponent()`.

**Warning signs:** Empty pairs array when the watched folder still exists at a different path.

### Pitfall 5: File Descriptor Leak on Repeated Start/Stop

**What goes wrong:** `stop()` is called but the cancel handler never runs (e.g., if the source was never resumed), leaving the fd open.

**Why it happens:** `setCancelHandler` only runs after `cancel()` on a resumed source. A source that was never `resume()`d may not call the cancel handler.

**How to avoid:** Always `resume()` immediately after creating the source. In the `start()` method, do not skip `resume()` under any conditions. Verify with `lsof -p <pid>` during testing that fd count doesn't grow.

**Warning signs:** "Too many open files" error after repeated folder navigation.

## Code Examples

Verified patterns from official sources and project conventions:

### DirectoryWatcher Core Setup
```swift
// Source: Apple DirectoryMonitor (ListerKit sample) + DispatchSource docs
// eventMask: .write fires on: file added to dir, file removed from dir, file renamed in dir

let fd = open(url.path, O_EVTONLY)
guard fd >= 0 else { return }

let source = DispatchSource.makeFileSystemObjectSource(
    fileDescriptor: fd,
    eventMask: .write,
    queue: dispatchQueue
)
source.setEventHandler { /* handle event */ }
source.setCancelHandler { close(fd) }
source.resume()
```

### DispatchWorkItem Debounce
```swift
// Source: DispatchWorkItem Apple docs + community pattern
// Cancel previous, schedule new

debounceWorkItem?.cancel()
let item = DispatchWorkItem { [weak self] in
    Task { @MainActor [weak self] in
        self?.performRescan()
    }
}
debounceWorkItem = item
DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: item)
```

### ImageCacheActor Targeted Eviction (new method needed)
```swift
// Add to ImageCacheActor -- follows existing evict() pattern

func remove(for url: URL) {
    guard storage[url] != nil else { return }
    evict(url)
    print("[cache] removed \(url.lastPathComponent) on external deletion")
}
```

### Selection Repair After Deletion
```swift
// Called when selectedID's image URL is in the removed set
// "next neighbor or previous if last" rule (Locked Decision)

private func repairSelectionAfterDeletion(oldPairs: [ImageCaptionPair], newPairs: [ImageCaptionPair]) {
    guard let sid = selectedID else {
        selectedID = newPairs.first?.id
        return
    }
    // Was the selected pair deleted?
    guard !newPairs.contains(where: { $0.id == sid }) else { return }

    // Find where it was in the old list
    if let oldIdx = oldPairs.firstIndex(where: { $0.id == sid }) {
        // Try next neighbor, fall back to previous
        let candidate = newPairs.indices.filter { $0 >= oldIdx }.first
            ?? newPairs.indices.last
        selectedID = candidate.map { newPairs[$0].id }
    } else {
        selectedID = newPairs.first?.id
    }
    detailID = selectedID
    _editingIsDirty = false  // silently discard (Locked Decision)
}
```

### Navigate to Parent on Watched Folder Deletion
```swift
// Walk up to nearest surviving ancestor

private func navigateToSurvivingAncestor(from url: URL) {
    var candidate = url.deletingLastPathComponent()
    let fm = FileManager.default
    while !fm.fileExists(atPath: candidate.path) && candidate.path != "/" {
        candidate = candidate.deletingLastPathComponent()
    }
    guard fm.fileExists(atPath: candidate.path),
          let root = rootDirectoryURL,
          candidate.path.hasPrefix(root.path) else {
        // Fallback to root
        if let root = rootDirectoryURL { navigateToFolder(root) }
        return
    }
    navigateToFolder(candidate)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| kqueue directly | `DispatchSource.makeFileSystemObjectSource` | macOS 10.6 (GCD) | Same kernel mechanism, Swift-friendly wrapper |
| FSEvents for all watching | VNODE for single-directory + FSEvents for recursive | Still valid distinction | Use VNODE here (flat directories only) |
| Manual fd polling | Event-driven DispatchSource | macOS 10.6 | No polling required |

**Deprecated/outdated:**
- Using `FileHandle.waitForDataInBackgroundAndNotify()` for directory watching: this is for pipe/socket data, not filesystem events. Not applicable here.
- Checking `source.handle` after cancel: handle is not valid after cancel.

## Open Questions

1. **Does `open(url.path, O_EVTONLY)` succeed while security-scoped access is active for a sandboxed app?**
   - What we know: `startAccessingSecurityScopedResource()` grants POSIX-level access within the sandbox; O_EVTONLY is a standard `open()` flag. The combination should work because the security scope extends to raw POSIX calls on URLs within the granted tree.
   - What's unclear: There is no explicit Apple documentation confirming O_EVTONLY works within a security-scoped bookmark grant. The STATE.md explicitly flags this as needing empirical validation.
   - Recommendation: **Wave 0 task: manually test O_EVTONLY open() on a security-scoped directory before building dependent logic.** Use a small standalone test that opens a picker, gets a bookmark, resolves it, calls startAccessing, then open(path, O_EVTONLY) and verifies fd >= 0.

2. **Does `scanCurrentDirectory()` reading the directory trigger a `.write` event (bounce-back loop)?**
   - What we know: Reading via `contentsOfDirectory` accesses directory entries. On HFS+/APFS this may or may not update the directory's modification time.
   - What's unclear: Empirically needs testing on the target macOS version (macOS 13/14/15).
   - Recommendation: Implement an `isRescanning` guard regardless; it's a trivial safeguard with no performance cost.

3. **Single vs. separate debounce timers for content and tree watchers?**
   - What we know: Both watchers can share a single debounce timer since the rescan updates both `pairs` and `folderTree`. Separate timers add complexity without clear benefit.
   - Recommendation: Single shared `debounceWorkItem`. The rescan function rebuilds both the file list and the folder tree.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Swift Testing (`import Testing`) |
| Config file | Embedded in `lora-datasetTests` target (no separate config file) |
| Quick run command | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests 2>&1 | tail -20` |
| Full suite command | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset 2>&1 | tail -30` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WATCH-01 | VNODE watcher fires callback when file added/deleted in directory | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DirectoryWatcherTests` | ❌ Wave 0 |
| WATCH-02 | pairs array updated after external file add/delete | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DirectoryWatcherTests/testFileListUpdatesOnAdd` | ❌ Wave 0 |
| WATCH-03 | Rapid events result in single rescan after 0.5s | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DirectoryWatcherTests/testDebounceCoalescesEvents` | ❌ Wave 0 |
| WATCH-04 | Watcher stops/starts on folder navigation | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DirectoryWatcherTests/testWatcherReplacedOnNavigation` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests 2>&1 | tail -20`
- **Per wave merge:** Full suite command above
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `lora-datasetTests/DirectoryWatcherTests.swift` -- covers WATCH-01, WATCH-02, WATCH-03, WATCH-04
- [ ] Add `remove(for:)` method to `ImageCacheActor` (needed by diff logic in Phase 11)

*Note: DirectoryWatcher tests operate on a real temp directory (created with `FileManager.default.createDirectory` in test setup, cleaned in teardown). No mock needed -- the watcher is thin and tests against the real filesystem in /tmp. Tests use `XCTestExpectation` or Swift Testing's async patterns with timeouts to wait for the debounce to fire.*

## Sources

### Primary (HIGH confidence)
- Apple `DISPATCH_SOURCE_TYPE_VNODE` documentation - VNODE event masks, DispatchSource lifecycle
- Apple `DirectoryMonitor.swift` (ListerKit sample) - canonical O_EVTONLY + DispatchSource pattern
- `DispatchWorkItem` Apple documentation - cancel/reschedule debounce pattern
- Project `DatasetViewModel.swift` - existing scanCurrentDirectory, navigateToFolder, triggerPrefetch patterns
- Project `ImageCacheActor.swift` - existing evict() pattern; basis for new remove(for:) method

### Secondary (MEDIUM confidence)
- [DispatchSource: Detecting changes in files and folders in Swift](https://swiftrocks.com/dispatchsource-detecting-changes-in-files-and-folders-in-swift) - Swift code patterns for VNODE; matches Apple sample
- [Using DispatchWorkItem to delay tasks](https://blog.natanrolnik.me/dispatch-work-item) - debounce cancel-and-reschedule idiom

### Tertiary (LOW confidence -- empirical validation needed)
- O_EVTONLY + security-scoped URL compatibility: inferred from POSIX-level sandbox access model; no explicit Apple doc found confirming this combination

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- DispatchSource VNODE is the well-documented standard for this exact problem; no alternatives needed
- Architecture: HIGH -- DirectoryWatcher + debounce pattern is canonical and matches existing project patterns
- Pitfalls: HIGH for fd lifecycle and MainActor dispatch; MEDIUM for sandbox O_EVTONLY (needs empirical test per STATE.md note)
- Cache integration: HIGH -- follows existing ImageCacheActor evict() pattern with trivial new `remove(for:)` method

**Research date:** 2026-03-16
**Valid until:** 2026-09-16 (DispatchSource API is stable; no fast-moving surface)
