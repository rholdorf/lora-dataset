# Roadmap: LoRA Dataset Browser

## Completed Milestones

- [v1.1 Finder Navigation](milestones/v1.1-ROADMAP.md) (Phases 1-4) - SHIPPED 2025-12-21
- [v1.2 Improvements](milestones/v1.2-ROADMAP.md) (Phase 5) - SHIPPED 2025-12-22
- [v1.3 Features](milestones/v1.3-ROADMAP.md) (Phase 6) - SHIPPED 2025-12-22
- [v1.4 Native OS Integration](milestones/v1.4-ROADMAP.md) (Phases 7-9) - SHIPPED 2026-03-16

## Current Milestone: v1.5 Performance & Live Sync

**Milestone Goal:** Finder-speed image navigation with intelligent caching and real-time filesystem monitoring for external changes.

### Phases

- [x] **Phase 10: Image Cache + Prefetch** - Sub-50ms image display via LRU cache and background neighbor prefetch (completed 2026-03-16)
- [x] **Phase 11: Filesystem Watchdog -- Structural Changes** - Silent file list updates when files are added or removed externally (completed 2026-03-16)
- [ ] **Phase 12: Filesystem Watchdog -- Caption Content Changes** - Automatic caption reload when external tools modify the selected caption file

## Phase Details

### Phase 10: Image Cache + Prefetch
**Goal**: Users experience Finder-speed image navigation with no perceptible load delay when moving between images
**Depends on**: Nothing (independent addition)
**Requirements**: CACHE-01, CACHE-02, CACHE-03, CACHE-04, CACHE-05, CACHE-06
**Success Criteria** (what must be TRUE):
  1. Pressing the arrow key to move to a previously visited image displays it in under 50ms (cache hit)
  2. Navigating to an image that was two positions ahead loads without a visible loading pause (prefetch hit)
  3. The app does not consume unbounded memory when browsing a large dataset -- cache evicts under memory pressure
  4. Rapidly pressing arrow keys does not cause wrong images to flash or linger from stale prefetch tasks
**Plans:** 2/2 plans complete
Plans:
- [ ] 10-01-PLAN.md -- ImageLoader + ImageCacheActor with LRU eviction, cost tracking, memory pressure, and unit tests
- [ ] 10-02-PLAN.md -- Integration: cache-first loading, prefetch wiring, spinner overlay, folder-change cache clear

### Phase 11: Filesystem Watchdog -- Structural Changes
**Goal**: The file list stays accurate when external tools add or delete image/caption pairs in the watched folder
**Depends on**: Phase 10
**Requirements**: WATCH-01, WATCH-02, WATCH-03, WATCH-04
**Success Criteria** (what must be TRUE):
  1. Dropping a new image into the open folder causes it to appear in the sidebar without any user action
  2. Deleting a file from Finder removes it from the sidebar list silently
  3. Bulk file additions (e.g., copying 50 files at once) do not cause rapid-fire UI refreshes -- only one rescan fires
  4. Navigating to a different folder stops watching the old folder and starts watching the new one
**Plans:** 2/2 plans complete
Plans:
- [ ] 11-01-PLAN.md -- DirectoryWatcher class (DispatchSource VNODE + debounce) + ImageCacheActor.remove(for:) + unit tests
- [ ] 11-02-PLAN.md -- ViewModel integration: watcher lifecycle, rescan diff, selection repair, cache eviction, folder tree updates

### Phase 12: Filesystem Watchdog -- Caption Content Changes
**Goal**: The caption editor reflects external edits automatically, with a safety prompt when the user has unsaved changes
**Depends on**: Phase 11
**Requirements**: WATCH-05, WATCH-06, WATCH-07, WATCH-08
**Success Criteria** (what must be TRUE):
  1. Editing the selected caption in an external text editor and saving causes the caption field to update automatically (when no local edits are in progress)
  2. Saving via Cmd+S does not trigger a spurious caption reload
  3. When the caption has unsaved local edits and the file changes externally, a prompt appears asking the user whether to reload -- edits are never silently discarded
**Plans**: TBD

## Progress

**Execution Order:** 10 -> 11 -> 12

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Directory Tree Navigation | v1.1 | 2/2 | Complete | 2025-12-21 |
| 2. Save Enhancements | v1.1 | 1/1 | Complete | 2025-12-21 |
| 3. Security & Persistence | v1.1 | 1/1 | Complete | 2025-12-21 |
| 4. Polish | v1.1 | 1/1 | Complete | 2025-12-21 |
| 5. Toolbar Integration | v1.2 | 1/1 | Complete | 2025-12-22 |
| 6. Session Restoration | v1.3 | 1/1 | Complete | 2025-12-22 |
| 7. NSTextView Caption Editor | v1.4 | 1/1 | Complete | 2026-03-16 |
| 8. Finder Context Menus | v1.4 | 1/1 | Complete | 2026-03-16 |
| 9. Quick Look Preview | v1.4 | 1/1 | Complete | 2026-03-16 |
| 10. Image Cache + Prefetch | 2/2 | Complete    | 2026-03-16 | - |
| 11. FS Watchdog -- Structural | 2/2 | Complete    | 2026-03-17 | - |
| 12. FS Watchdog -- Captions | v1.5 | 0/? | Not started | - |
