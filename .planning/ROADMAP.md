# Roadmap: LoRA Dataset Browser v1.1

## Overview

Transform the app from a single-directory viewer into a Finder-like dataset browser. Add a sidebar folder tree for navigation, implement save shortcuts and dirty indicators, handle security-scoped bookmarks for directory traversal, and polish to native macOS standards.

## Domain Expertise

None

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): Planned milestone work
- Decimal phases (e.g., 2.1): Urgent insertions (marked with INSERTED)

- [x] **Phase 1: Directory Tree Navigation** - Sidebar with expandable folder tree for browsing directories (Complete)
- [ ] **Phase 2: Save Enhancements** - Cmd+S shortcut, File menu integration, dirty indicator
- [ ] **Phase 3: Security & Persistence** - Handle security-scoped bookmarks when navigating to new directories
- [ ] **Phase 4: Polish** - Native macOS refinements and edge cases

## Phase Details

### Phase 1: Directory Tree Navigation
**Goal**: Replace current flat file list with expandable folder tree in sidebar
**Depends on**: Nothing (first phase)
**Research**: Likely (SwiftUI tree patterns)
**Research topics**: SwiftUI OutlineGroup for file trees, FileManager directory enumeration, sidebar disclosure patterns
**Plans**: TBD

Plans:
- [x] 01-01: FileNode model and ViewModel folder tree state
- [x] 01-02: Folder tree view and navigation UI

### Phase 2: Save Enhancements
**Goal**: Add Cmd+S keyboard shortcut, File → Save menu item, and visual dirty indicator
**Depends on**: Phase 1
**Research**: Unlikely (established SwiftUI patterns)
**Plans**: TBD

Plans:
- [ ] 02-01: TBD

### Phase 3: Security & Persistence
**Goal**: Handle security-scoped bookmarks when user navigates to directories outside original selection
**Depends on**: Phase 1
**Research**: Likely (bookmark inheritance behavior)
**Research topics**: Security-scoped bookmark coverage for subdirectories, creating new bookmarks on navigation
**Plans**: TBD

Plans:
- [ ] 03-01: TBD

### Phase 4: Polish
**Goal**: Refine UI/UX to feel like a native Apple application
**Depends on**: Phases 2, 3
**Research**: Unlikely (internal patterns)
**Plans**: TBD

Plans:
- [ ] 04-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Directory Tree Navigation | 2/2 | Complete | 2025-12-21 |
| 2. Save Enhancements | 0/? | Not started | - |
| 3. Security & Persistence | 0/? | Not started | - |
| 4. Polish | 0/? | Not started | - |
