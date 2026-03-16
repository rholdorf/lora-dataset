---
phase: 11-filesystem-watchdog-structural-changes
plan: "02"
subsystem: filesystem-watcher
tags: [swift, dispatch-source, debounce, live-sync, cache-eviction, selection-repair]

# Dependency graph
requires:
  - phase: 11-filesystem-watchdog-structural-changes
    plan: "01"
    provides: [DirectoryWatcher, ImageCacheActor.remove(for:)]
provides:
  - DatasetViewModel watchdog integration (startWatching, stopWatching, performContentRescan, performTreeRescan, navigateToSurvivingAncestor)
  - Live sidebar file list sync on external file add/delete/replace
  - Debounced rescan with diff-based cache eviction and selection repair
  - Folder tree live updates
  - Parent-folder navigation on watched folder deletion
affects: [lora-dataset/lora-dataset/DatasetViewModel.swift, Phase 12]

# Tech tracking
tech-stack:
  added: []
  patterns: [debounced-diff-rescan, cache-evict-on-rescan, selection-repair-by-url, bounce-back-guard]

key-files:
  created: []
  modified:
    - lora-dataset/lora-dataset/DatasetViewModel.swift

key-decisions:
  - "Two separate watchers: contentWatcher on directoryURL, treeWatcher on rootDirectoryURL (only when they differ) — content watcher handles file list, tree watcher handles folder structure"
  - "Force-evict surviving URLs on every rescan callback — .write event implies directory changed, evicting all cached entries for the directory is cheap and guarantees replaced files never show stale"
  - "Selection repair matches by imageURL not UUID — scanCurrentDirectory regenerates UUIDs, so post-rescan selection must be matched by stable imageURL identity"
  - "isRescanning guard prevents bounce-back infinite loop — reading directory contents can trigger .write VNODE events on some FS implementations"
  - "startWatching() called after chooseDirectory(), restorePreviousDirectoryIfAvailable(), and navigateToFolder(); stopWatching() called before navigateToFolder() for WATCH-04 compliance"

patterns-established:
  - "Watchdog pattern: contentWatcher + treeWatcher with shared serial queue, all callbacks dispatch to @MainActor via Task"
  - "Rescan diff pattern: capture oldURLs, call scanCurrentDirectory(), compute removed/added/surviving sets, evict+repair"
  - "[watchdog] print prefix for all debug logging (consistent with [cache] and [saveSelected] conventions)"

requirements-completed: [WATCH-01, WATCH-02, WATCH-03, WATCH-04]

# Metrics
duration: 6min
completed: 2026-03-16
---

# Phase 11 Plan 02: Watchdog Integration into DatasetViewModel Summary

**DatasetViewModel wired with two DirectoryWatcher instances for live file-list and folder-tree sync: debounced diff-rescan with cache eviction for deleted and replaced files, URL-based selection repair, and parent-folder navigation on watched folder deletion.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-16T22:08:45Z
- **Completed:** 2026-03-16T22:14:45Z
- **Tasks:** 1 complete (Task 2 is a human-verify checkpoint, pending user verification)
- **Files modified:** 1

## Accomplishments

- Added `contentWatcher` and `treeWatcher` DirectoryWatcher properties with `isRescanning` bounce-back guard
- `startWatching()` creates two watchers on a shared serial utility queue; tree watcher only when root differs from content directory
- `stopWatching()` cancels and nils both watchers; called before folder navigation (WATCH-04)
- `performContentRescan()`: captures old/new URL sets, evicts removed and surviving URLs from cache, repairs selection by imageURL, re-triggers prefetch, rebuilds folder tree
- `performTreeRescan()`: rebuilds folder tree, detects if content directory was deleted
- `navigateToSurvivingAncestor()`: walks up directory tree to nearest existing ancestor within root scope
- All three entry points (`chooseDirectory`, `restorePreviousDirectoryIfAvailable`, `navigateToFolder`) now call start/stop watching
- Full test suite passes: 29 unit tests green (no regressions)

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire watchdog into DatasetViewModel** - `2127545` (feat)
2. **Task 2: Verify filesystem watchdog behavior** - PENDING (human-verify checkpoint)

## Files Created/Modified

- `lora-dataset/lora-dataset/DatasetViewModel.swift` - Added 156 lines: watchdog properties, lifecycle methods, rescan logic, selection repair, ancestor navigation

## Decisions Made

- Two separate watchers (content + tree) with shared serial queue: content watcher fires on image file changes in the current directory, tree watcher fires on subfolder structure changes at root. Using a shared queue means they never race.
- Force-evict all surviving URL cache entries on every rescan: since .write fires because something changed in the directory, invalidating surviving entries is safe and cheap — they reload on next display via cache-miss path.
- Selection repair matches by imageURL (not UUID): `scanCurrentDirectory()` creates fresh UUIDs on every call, so post-rescan selection must identify the previously-selected pair by its stable `imageURL`.
- `isRescanning` guard prevents bounce-back: reading directory contents can trigger a second .write VNODE event, which would cause infinite rescan loops without this guard.

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. Compilation succeeded on first attempt. All 29 unit tests passed.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Watchdog integration complete — after human verification (Task 2 checkpoint), Phase 11 is functionally complete
- Phase 12 (dirty-caption conflict prompt) can proceed once Task 2 is verified
- The `navigateToSurvivingAncestor` and `performTreeRescan` deleted-folder paths will need manual testing as part of the Task 2 checkpoint

---
*Phase: 11-filesystem-watchdog-structural-changes*
*Completed: 2026-03-16*
