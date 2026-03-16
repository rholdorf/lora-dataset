---
phase: 08-finder-context-menus
plan: 01
subsystem: ui
tags: [swift, swiftui, appkit, quicklook, nsworkspace, context-menu, finder, terminal]

# Dependency graph
requires:
  - phase: 04-folder-navigation
    provides: FolderNodeView and FileNode types used for sidebar rows
  - phase: 01-core
    provides: ImageCaptionPair with imageURL used for file operations
provides:
  - Right-click context menus on file rows (Reveal in Finder, Open With, Quick Look)
  - Right-click context menus on folder rows (Open in Finder, Open in Terminal)
  - QLPreviewHelper data source for QLPreviewPanel integration
  - DatasetViewModel action methods for all OS-native file operations
affects: [09-quick-look-panel]

# Tech tracking
tech-stack:
  added: [Quartz/QuickLookUI, UniformTypeIdentifiers]
  patterns: [NSWorkspace for file operations, QLPreviewPanelDataSource protocol, @ViewBuilder context menu helper]

key-files:
  created:
    - lora-dataset/lora-dataset/QLPreviewHelper.swift
  modified:
    - lora-dataset/lora-dataset/DatasetViewModel.swift
    - lora-dataset/lora-dataset/ContentView.swift

key-decisions:
  - "QLPreviewHelper is deliberately minimal — Phase 9 will build full QLPreviewPanel with spacebar support"
  - "openWithMenu implemented as @ViewBuilder on ContentView — NSWorkspace calls inline are acceptable since .contextMenu rebuilds each time"
  - "App icons resized to 16x16 to prevent oversized menu items"
  - "quickLook toggles panel visibility (orderOut if visible) to allow dismissal via same menu item"
  - "NSApp.keyWindow?.makeFirstResponder(nil) before QLPreviewPanel to prevent NSTextView hijack"

patterns-established:
  - "Context menu helpers as @ViewBuilder private functions on the view that owns the rows"
  - "ViewModel action methods call NSWorkspace/QLPreviewPanel directly on @MainActor"
  - "Use NSWorkspace.shared.open(_:withApplicationAt:configuration:completionHandler:) not deprecated bundle ID API"

requirements-completed: [CTXM-01, CTXM-02, CTXM-03, CTXM-04, CTXM-05]

# Metrics
duration: 20min
completed: 2026-03-16
---

# Phase 8 Plan 1: Finder Context Menus Summary

**Right-click context menus on sidebar file rows (Reveal in Finder, Open With submenu with icons, Quick Look) and folder rows (Open in Finder, Open in Terminal) via NSWorkspace and QLPreviewPanel**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-03-16T02:07:00Z
- **Completed:** 2026-03-16T02:27:00Z
- **Tasks:** 2 of 2 auto tasks complete (Task 3 is human-verify checkpoint)
- **Files modified:** 3

## Accomplishments
- Created QLPreviewHelper.swift with QLPreviewPanelDataSource conformance for Quick Look integration
- Added 5 ViewModel action methods: revealInFinder, openInFinder, openInTerminal, openWith, quickLook
- Added file row context menus with Reveal in Finder, Open With (full app list with icons), and Quick Look
- Added folder row context menus with Open in Finder and Open in Terminal
- Open With submenu shows default app first (bold), other apps alphabetically with icons, and Other... at bottom

## Task Commits

Each task was committed atomically:

1. **Task 1: Create QLPreviewHelper and add ViewModel action methods** - `a9cfaf7` (feat)
2. **Task 2: Add context menus to file and folder rows** - `e4bc143` (feat)

## Files Created/Modified
- `lora-dataset/lora-dataset/QLPreviewHelper.swift` - Minimal QLPreviewPanelDataSource for Quick Look; Phase 9 extends this
- `lora-dataset/lora-dataset/DatasetViewModel.swift` - Added qlPreviewHelper property, revealInFinder, openInFinder, openInTerminal, openWith, quickLook methods; added import Quartz
- `lora-dataset/lora-dataset/ContentView.swift` - Added .contextMenu to file rows and FolderNodeView, openWithMenu @ViewBuilder helper, appName/appIcon/chooseApp helpers; added import UniformTypeIdentifiers

## Decisions Made
- QLPreviewHelper is deliberately minimal — Phase 9 will build full QLPreviewPanel infrastructure with spacebar support
- openWithMenu is a @ViewBuilder private function on ContentView; NSWorkspace calls inline are acceptable since .contextMenu rebuilds each time it appears
- App icons resized to 16x16 NSSize to prevent oversized context menu items
- quickLook method toggles: orderOut if panel visible, show otherwise — allows same menu item to dismiss
- NSApp.keyWindow?.makeFirstResponder(nil) called before showing QLPreviewPanel to prevent NSTextView caption editor from hijacking the panel

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Context menus compile and build cleanly
- Human verification (Task 3 checkpoint) required before marking plan complete
- Phase 9 (Quick Look Panel) can extend QLPreviewHelper with spacebar support, NSResponder chain integration, and full panel lifecycle management

---
*Phase: 08-finder-context-menus*
*Completed: 2026-03-16*
