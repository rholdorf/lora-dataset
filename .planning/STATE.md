---
gsd_state_version: 1.0
milestone: v1.5
milestone_name: Performance & Live Sync
status: verifying
stopped_at: "Completed 11-02 Task 1: watchdog wired into DatasetViewModel. Awaiting human-verify checkpoint (Task 2)."
last_updated: "2026-03-16T22:18:23.526Z"
last_activity: 2026-03-16 — Phase 11 Plan 02 complete (watchdog integration + diff rescan + selection repair)
progress:
  total_phases: 3
  completed_phases: 2
  total_plans: 4
  completed_plans: 4
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-16)

**Core value:** View images alongside their caption files and edit captions in place for LoRA training datasets
**Current focus:** Phase 11 — Filesystem Watchdog Structural Changes

## Current Position

Phase: 11 of 12 (Filesystem Watchdog Structural Changes)
Plan: 02 complete (awaiting human-verify checkpoint) — watchdog wired into DatasetViewModel
Status: Verifying — Plan 02 Task 1 done, human-verify checkpoint pending
Last activity: 2026-03-16 — Phase 11 Plan 02 complete (watchdog integration + diff rescan + selection repair)

Progress: [██████████] 100% (4/4 plans complete)

## Performance Metrics

**Velocity:**
- Total plans completed: 10
- Average duration: ~30 min
- Total execution time: ~5h

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 1 | 2 | 1h 29m | 45 min |
| 2 | 1 | 11 min | 11 min |
| 3 | 1 | 2h 15m | 2h 15m |
| 4 | 1 | 20 min | 20 min |
| 5 | 1 | 20 min | 20 min |
| 6 | 1 | 3 min | 3 min |
| 7 | 1 | 45 min | 45 min |
| 8 | 1 | 20 min | 20 min |
| 9 | 1 | manual | iterative |
| 10 (P01) | 1 | 5 min | 5 min |
| 10 (P02) | 1 | 5 min | 5 min |
| Phase 11 P01 | 3m | 1 tasks | 3 files |
| Phase 11 P02 | 6m | 1 tasks | 1 files |

## Accumulated Context

### Decisions Made (v1.4)

| Phase | Decision | Rationale |
|-------|----------|-----------|
| 07 | NSTextView subclass for grammar underlines | Standard NSTextView doesn't reliably show grammar check |
| 07 | LoRA-safe defaults (no smart quotes) | Protects training data from punctuation corruption |
| 08 | QLPreviewHelper as minimal data source | Simple approach that works; no AppDelegate needed |
| 09 | NSEvent local key monitor for QL navigation | QLPreviewPanel steals focus; monitor intercepts keys reliably |
| 09 | Async image loading via Task.detached | Prevents main thread blocking during rapid navigation |

### Decisions Made (v1.5 Phase 10)

| Phase | Decision | Rationale |
|-------|----------|-----------|
| 10 | Adaptive cache budget: 15% of physicalMemory | Better than fixed 200MB — scales to available RAM on each machine |
| 10 | CGImageSource thumbnail decode (not NSImage(contentsOf:)) | Decodes at display size, avoids full-resolution memory load, immediate decode via kCGImageSourceShouldCacheImmediately |
| 10 | [URL] access-order array + dictionary for LRU | Simpler than doubly-linked list; acceptable for dataset sizes in the hundreds |
| 10 | NSImage @unchecked @retroactive Sendable at file scope | Required for actor isolation — NSImage is safe once drawn |
| 10 | prefetchTasks is private(set) not private | Tests can inspect task dictionary without a separate accessor |
| 10 | loadImageForSelection uses Task { @MainActor in } not Task.detached | Enables direct access to actor-isolated vm.imageCache and vm.triggerPrefetch |
| 10 | Spinner overlays previous image at opacity 0.3 | Preserves visual context during slow cache misses; less jarring than blank frame |

### Key Decisions Pending (v1.5)

- Phase 12: exact UX for dirty-caption conflict prompt (style, button labels, dismiss behavior)

### Decisions Made (v1.5 Phase 11)

| Phase | Decision | Rationale |
|-------|----------|-----------|
| 11 | DispatchSource VNODE .write event mask fires reliably for file add/delete | Empirically validated by DirectoryWatcherTests — blocker resolved |
| 11 | cancel-and-reschedule DispatchWorkItem for debounce (not Timer) | Stays on watcher serial queue, no main thread coupling |
| 11 | O_EVTONLY file descriptor for directory watching | Prevents directory from blocking unmount |
| 11 | Two separate watchers: contentWatcher on directoryURL, treeWatcher on rootDirectoryURL (only when they differ) | Content watcher handles file list; tree watcher handles folder structure; shared serial queue prevents races |
| 11 | Force-evict all surviving URL cache entries on every rescan | .write event implies directory changed; cheap eviction guarantees replaced files never show stale content |
| 11 | Selection repair matches by imageURL not UUID | scanCurrentDirectory regenerates UUIDs on every call; post-rescan selection must match by stable imageURL identity |
| 11 | isRescanning guard prevents bounce-back infinite loop | Reading directory contents can trigger .write VNODE events on some FS implementations |

### Blockers/Concerns

(None — Phase 11 VNODE .write blocker resolved empirically in Plan 01 tests)

## Session Continuity

Last session: 2026-03-16T22:18:23.524Z
Stopped at: Completed 11-02 Task 1: watchdog wired into DatasetViewModel. Awaiting human-verify checkpoint (Task 2).
Next: Human verification of 8 test scenarios (file add/delete/bulk/navigation/tree/replacement/caption). After approval, Phase 11 complete; Phase 12 next.
