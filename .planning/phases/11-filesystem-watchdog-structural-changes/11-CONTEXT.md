# Phase 11: Filesystem Watchdog -- Structural Changes - Context

**Gathered:** 2026-03-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Silent file list updates when files are added or removed externally. The sidebar file list and folder tree stay accurate without any user action. Covers requirements WATCH-01 through WATCH-04. Caption content watching (WATCH-05 through WATCH-08) is Phase 12.

</domain>

<decisions>
## Implementation Decisions

### Selection behavior on deletion
- When the selected image is deleted externally, jump to the next neighbor in the sorted list (or previous if it was the last item)
- If the selected image's caption file is deleted but the image remains, clear the caption editor and treat as a new image (saving would create a new .txt file)
- When all images are deleted, show empty sidebar + blank detail pane (same as opening an empty folder today, no special message)
- If user has unsaved caption edits and the corresponding image is deleted externally, silently discard edits and move to next neighbor -- no prompt or toast

### New file appearance
- Silent sorted insertion -- new files slot into alphabetical position with no animation or highlight
- Preserve scroll position and current selection when the file list updates
- Auto-pair by basename -- same pairing logic as scanCurrentDirectory (match image.png with image.txt)
- Renames treated as delete + add -- no rename tracking. DispatchSource doesn't distinguish renames anyway

### Folder tree updates
- Watch folder tree too -- new subfolders appear and deleted subfolders disappear live
- If the currently-viewed folder is deleted externally, navigate to its parent folder
- Preserve folder expansion state (expandedPaths) across tree rebuilds
- If currently-viewed folder's parent is also deleted, walk up to the nearest surviving ancestor (or root)

### Cache interaction
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

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scanCurrentDirectory()`: Current directory scanning logic -- can be reused as the rescan function after debounce fires. Already handles pairing, sorting, and selection restoration.
- `navigateToFolder()`: Handles folder switch with cache clear and prefetch. Can be reused when current folder is deleted (navigate to parent).
- `buildFolderTree(from:)`: Recursive tree builder -- can be re-invoked to rebuild tree on structural changes.
- `expandedPaths`: Already persisted in UserDefaults -- tree rebuild can restore expansion state.
- `triggerPrefetch(aroundID:)`: Existing prefetch logic for ±2 window -- call after rescan to refresh prefetch window.
- `ImageCacheActor`: Has `clear()` but will need per-URL `remove(for:)` for targeted eviction on file deletion.

### Established Patterns
- `@MainActor` ViewModel with `@Published` properties -- watchdog callbacks should dispatch to main actor
- `Task.detached(priority: .utility)` for background work -- watcher setup follows this pattern
- `[prefix]` debug logging -- use `[watchdog]` prefix
- Security-scoped access via `startSecurityScopedAccess()` -- watcher needs active security scope

### Integration Points
- `navigateToFolder()` and `chooseDirectory()` -- start/stop watcher when folder changes
- `scanCurrentDirectory()` -- debounced rescan target
- `pairs` array -- diffing old vs new to detect adds/deletes for cache management
- `selectedID` -- preserve across rescans, update if selected file deleted
- `folderTree` -- rebuild on folder structure changes
- `prefetchTasks` -- cancel tasks for deleted files, re-trigger after rescan

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 11-filesystem-watchdog-structural-changes*
*Context gathered: 2026-03-16*
