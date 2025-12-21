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
- [x] **Phase 2: Save Enhancements** - Cmd+S shortcut, File menu integration, dirty indicator (Complete)
- [x] **Phase 3: Security & Persistence** - Expansion state persistence with DisclosureGroup + UserDefaults (Complete)
- [x] **Phase 4: Polish** - Native macOS refinements and edge cases (Complete)

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
**Plans**: 1

Plans:
- [x] 02-01: Save shortcut, menu, and dirty indicator

### Phase 3: Security & Persistence
**Goal**: Persist folder tree expansion state between app sessions
**Depends on**: Phase 1
**Research**: Unlikely (established SwiftUI patterns)
**Plans**: 1

Plans:
- [x] 03-01: Expansion state persistence (DisclosureGroup + UserDefaults)

### Phase 4: Polish
**Goal**: Refine UI/UX to feel like a native Apple application
**Depends on**: Phases 2, 3
**Research**: Unlikely (internal patterns)
**Plans**: 1

Plans:
- [x] 04-01: Native folder tree styling with manual disclosure

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Directory Tree Navigation | 2/2 | Complete | 2025-12-21 |
| 2. Save Enhancements | 1/1 | Complete | 2025-12-21 |
| 3. Security & Persistence | 1/1 | Complete | 2025-12-21 |
| 4. Polish | 1/1 | Complete | 2025-12-21 |

**Milestone v1.1 Complete!**
