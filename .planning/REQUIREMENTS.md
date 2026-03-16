# Requirements: LoRA Dataset Browser

**Defined:** 2026-03-16
**Core Value:** View images alongside their caption files and edit captions in place for LoRA training datasets

## v1.5 Requirements

Requirements for v1.5 Performance & Live Sync. Each maps to roadmap phases.

### Cache & Prefetch

- [x] **CACHE-01**: Images load from in-memory LRU cache with sub-50ms display on cache hit
- [x] **CACHE-02**: Cache uses decoded pixel byte cost (width × height × 4) for memory accounting
- [x] **CACHE-03**: ±2 neighboring images are prefetched in background on selection change
- [x] **CACHE-04**: Images are decoded via CGImageSource at display size for faster loading
- [x] **CACHE-05**: Cache evicts entries under system memory pressure (partial on warning, full on critical)
- [x] **CACHE-06**: Stale prefetch tasks are cancelled when user navigates past them

### Filesystem Watchdog

- [x] **WATCH-01**: Directory-level VNODE watcher detects file additions, deletions, and renames
- [ ] **WATCH-02**: File list updates silently when files are added or removed externally
- [x] **WATCH-03**: Watchdog events are debounced (0.5s) to prevent UI thrashing
- [x] **WATCH-04**: Watchdog tears down and rebuilds when navigating to a different folder
- [ ] **WATCH-05**: Caption file watcher detects external modifications to the selected caption
- [ ] **WATCH-06**: Caption reloads silently when modified externally and caption is not dirty
- [ ] **WATCH-07**: App's own save (Cmd+S) does not trigger a false reload (self-write suppression)
- [ ] **WATCH-08**: When caption has unsaved edits and file changes externally, user is prompted before reload

## Future Requirements

### Performance Optimizations

- **PERF-01**: Disk cache for decoded images (mtime invalidation, eviction policies)
- **PERF-02**: Thumbnail strip in sidebar for visual preview

### Watchdog Enhancements

- **WEXT-01**: Cross-folder prefetch when navigating between directories
- **WEXT-02**: User-configurable cache size slider

## Out of Scope

| Feature | Reason |
|---------|--------|
| Disk cache for decoded images | High complexity (mtime invalidation, eviction), low value given OS filesystem caching |
| Thumbnail sidebar strip | Separate milestone, requires second cache at thumbnail resolution |
| Cross-folder prefetch | Complex coordination, not worth effort for solo use |
| User-configurable cache size | Automatic pressure-based eviction handles the right behavior |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CACHE-01 | Phase 10 | Complete |
| CACHE-02 | Phase 10 | Complete |
| CACHE-03 | Phase 10 | Complete |
| CACHE-04 | Phase 10 | Complete |
| CACHE-05 | Phase 10 | Complete |
| CACHE-06 | Phase 10 | Complete |
| WATCH-01 | Phase 11 | Complete |
| WATCH-02 | Phase 11 | Pending |
| WATCH-03 | Phase 11 | Complete |
| WATCH-04 | Phase 11 | Complete |
| WATCH-05 | Phase 12 | Pending |
| WATCH-06 | Phase 12 | Pending |
| WATCH-07 | Phase 12 | Pending |
| WATCH-08 | Phase 12 | Pending |

**Coverage:**
- v1.5 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-16*
*Last updated: 2026-03-16 after roadmap creation*
