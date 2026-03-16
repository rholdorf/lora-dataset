# Roadmap: LoRA Dataset Browser

## Completed Milestones

- [v1.1 Finder Navigation](milestones/v1.1-ROADMAP.md) (Phases 1-4) - SHIPPED 2025-12-21
- [v1.2 Improvements](milestones/v1.2-ROADMAP.md) (Phase 5) - SHIPPED 2025-12-22
- [v1.3 Features](milestones/v1.3-ROADMAP.md) (Phase 6) - SHIPPED 2025-12-22

## Current Milestone: v1.4 Native OS Integration

**Goal:** Deep macOS integration — native NSTextView caption editor with spell/grammar check, Finder context menus on sidebar items, and Quick Look preview panel.

## Phases

- [ ] **Phase 7: NSTextView Caption Editor** - Replace TextEditor with full-featured NSTextView for spell check, grammar, dictionary lookup, and LoRA-safe substitution settings
- [ ] **Phase 8: Finder Context Menus** - Add right-click context menus to sidebar file and folder rows with Reveal in Finder, Open in Finder, Open With, and Quick Look actions
- [ ] **Phase 9: Quick Look Preview** - Wire spacebar and context menu to open the native floating QLPreviewPanel for the selected image

## Phase Details

### Phase 7: NSTextView Caption Editor
**Goal**: Users can edit captions in a full native text editor with spell check, grammar check, dictionary lookup, and no smart-punctuation corruption
**Depends on**: Phase 6
**Requirements**: EDIT-01, EDIT-02, EDIT-03, EDIT-04, EDIT-05
**Success Criteria** (what must be TRUE):
  1. Misspelled words in the caption editor show red underlines as the user types
  2. User can right-click any word in the caption editor and see a "Look Up" menu item that opens the system dictionary
  3. Smart quotes and smart dashes do not activate when the user types quotation marks or double-hyphens in the caption editor
  4. Grammar issues show green underlines in the caption editor
  5. Spell checking language switches automatically when the user types in a different language without any manual setting
**Plans:** 1 plan
Plans:
- [ ] 07-01-PLAN.md — Create NSTextView caption editor with LoRA-safe settings and integrate into ContentView

### Phase 8: Finder Context Menus
**Goal**: Users can right-click any sidebar item to access OS-native file operations without leaving the app
**Depends on**: Phase 7
**Requirements**: CTXM-01, CTXM-02, CTXM-03, CTXM-04, CTXM-05
**Success Criteria** (what must be TRUE):
  1. Right-clicking a file row in the sidebar shows a context menu
  2. Right-clicking a folder row in the sidebar shows a context menu
  3. "Reveal in Finder" (for files) and "Open in Finder" (for folders) in the context menu opens Finder with the item highlighted or the folder opened
  4. "Open With" in the context menu shows a submenu of applications that can open the image file
  5. "Quick Look" in the context menu triggers the Quick Look panel for that file
**Plans**: TBD

### Phase 9: Quick Look Preview
**Goal**: Users can preview the selected image in the native floating Quick Look panel using spacebar
**Depends on**: Phase 8
**Requirements**: QLPV-01, QLPV-02, QLPV-03
**Success Criteria** (what must be TRUE):
  1. Pressing spacebar while a file is selected opens the native Quick Look floating panel showing the image
  2. Pressing spacebar again or pressing Escape dismisses the Quick Look panel
  3. The Quick Look panel appears as a floating window (not a sheet or popover) above the app
**Plans**: TBD

## Progress

**Execution Order:** 7 → 8 → 9

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Directory Tree Navigation | v1.1 | 2/2 | Complete | 2025-12-21 |
| 2. Save Enhancements | v1.1 | 1/1 | Complete | 2025-12-21 |
| 3. Security & Persistence | v1.1 | 1/1 | Complete | 2025-12-21 |
| 4. Polish | v1.1 | 1/1 | Complete | 2025-12-21 |
| 5. Toolbar Integration | v1.2 | 1/1 | Complete | 2025-12-22 |
| 6. Session Restoration | v1.3 | 1/1 | Complete | 2025-12-22 |
| 7. NSTextView Caption Editor | v1.4 | 0/1 | Not started | - |
| 8. Finder Context Menus | v1.4 | 0/? | Not started | - |
| 9. Quick Look Preview | v1.4 | 0/? | Not started | - |
