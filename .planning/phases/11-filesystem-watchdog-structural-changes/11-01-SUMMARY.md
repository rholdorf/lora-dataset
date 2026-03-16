---
phase: 11-filesystem-watchdog-structural-changes
plan: "01"
subsystem: filesystem-watcher
tags: [swift, dispatch-source, vnode, debounce, tdd, cache]
dependency_graph:
  requires: []
  provides: [DirectoryWatcher, ImageCacheActor.remove(for:)]
  affects: [lora-dataset/lora-dataset/DirectoryWatcher.swift, lora-dataset/lora-dataset/ImageCacheActor.swift]
tech_stack:
  added: [DispatchSource.makeFileSystemObjectSource, O_EVTONLY fd, DispatchWorkItem debounce]
  patterns: [TDD red-green, cancel-and-reschedule debounce, actor targeted eviction]
key_files:
  created:
    - lora-dataset/lora-dataset/DirectoryWatcher.swift
    - lora-dataset/lora-datasetTests/DirectoryWatcherTests.swift
  modified:
    - lora-dataset/lora-dataset/ImageCacheActor.swift
decisions:
  - "DispatchSource VNODE .write event mask fires reliably for file add/delete on macOS — empirically validated by tests"
  - "cancel-and-reschedule DispatchWorkItem pattern for debounce (not Timer) — stays on the watcher's serial queue, no main thread coupling"
  - "O_EVTONLY file descriptor — prevents directory from blocking unmount"
  - "Default debounceDelay = 0.5s injected via init parameter — tests use shorter delay for speed"
metrics:
  duration: "3 minutes"
  completed_date: "2026-03-16"
  tasks_completed: 1
  files_changed: 3
---

# Phase 11 Plan 01: DirectoryWatcher + ImageCacheActor.remove Summary

**One-liner:** DispatchSource VNODE filesystem watcher with cancel-and-reschedule debounce and targeted single-URL cache eviction for watchdog-driven invalidation.

## What Was Built

### DirectoryWatcher.swift

A `final class DirectoryWatcher` wrapping `DispatchSource.makeFileSystemObjectSource` with:

- `O_EVTONLY` file descriptor (event-only — does not prevent unmounting)
- `.write` event mask (fires for file add/delete/rename in directory)
- Cancel-and-reschedule `DispatchWorkItem` debounce (default 0.5 s)
- Idempotent `start()` / `stop()` lifecycle
- `deinit` calls `stop()` to guarantee fd cleanup
- `setCancelHandler { close(fd) }` — fd lifetime tied to source lifecycle

### ImageCacheActor.remove(for:)

Added `func remove(for url: URL)` public method to `ImageCacheActor`:
- Delegates to existing private `evict(_:)` helper (removes from storage + accessOrder, decrements totalCost)
- Guard returns immediately for unknown URLs (no-op)
- Placed after `clear()` in the Public API section

### DirectoryWatcherTests.swift

9 new tests covering:
1. `testCallbackFiresOnFileAdd` — watcher fires within 2 s on file creation
2. `testCallbackFiresOnFileDelete` — watcher fires within 2 s on file deletion
3. `testStopPreventsCallbacks` — no callback after `stop()` is called
4. `testDebounceCoalescesRapidEvents` — 5 rapid writes coalesce to exactly 1 callback
5. `testDeinitCallsStop` — deallocation prevents subsequent callbacks
6. `testWatcherReplacedOnNavigation` — WATCH-04 lifecycle: stopped watcher does not fire; active watcher fires
7. `testRemoveEvictsSingleEntry` — `remove(for:)` clears entry and totalCost
8. `testRemoveIsNoOpForUnknownURL` — `remove(for:)` on missing key does not crash
9. `testRemoveDecrementsCorrectCost` — `remove(for:)` decrements only the evicted entry's cost

## TDD Execution

| Phase | Action | Outcome |
|-------|--------|---------|
| RED | Created `DirectoryWatcherTests.swift` with 9 failing tests | Build failed: `Cannot find 'DirectoryWatcher' in scope` |
| GREEN | Created `DirectoryWatcher.swift` + added `remove(for:)` to `ImageCacheActor` | All 9 new tests pass, 20 existing tests pass |

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check

### Files exist:
- `lora-dataset/lora-dataset/DirectoryWatcher.swift` — FOUND
- `lora-dataset/lora-dataset/ImageCacheActor.swift` — FOUND (modified)
- `lora-dataset/lora-datasetTests/DirectoryWatcherTests.swift` — FOUND

### Commits exist:
- `9f20141` — test(11-01): add failing tests for DirectoryWatcher and ImageCacheActor.remove(for:)
- `9a20f35` — feat(11-01): implement DirectoryWatcher and ImageCacheActor.remove(for:)

### Verification commands:
- `grep -c "func remove(for url: URL)" ...ImageCacheActor.swift` → 1
- All 9 DirectoryWatcherTests pass
- Full test suite (29 tests) green

## Self-Check: PASSED
