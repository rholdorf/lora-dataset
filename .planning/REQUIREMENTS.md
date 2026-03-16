# Requirements: LoRA Dataset Browser

**Defined:** 2026-03-15
**Core Value:** View images alongside their caption files and edit captions in place for LoRA training datasets

## v1.4 Requirements

Requirements for v1.4 Native OS Integration. Each maps to roadmap phases.

### Caption Editor

- [ ] **EDIT-01**: Caption text uses native NSTextView with continuous spell checking (red underlines on unknown words)
- [ ] **EDIT-02**: Caption text has grammar checking enabled (green underlines)
- [ ] **EDIT-03**: User can right-click for "Look Up" dictionary definitions on any word
- [ ] **EDIT-04**: Smart quotes and smart dashes are disabled by default to protect LoRA training data
- [ ] **EDIT-05**: Auto-language detection works natively via NSSpellChecker

### Context Menu

- [ ] **CTXM-01**: User can right-click a file in sidebar to see a context menu
- [ ] **CTXM-02**: User can right-click a folder in sidebar to see a context menu
- [ ] **CTXM-03**: Context menu includes "Reveal in Finder" (files) / "Open in Finder" (folders)
- [ ] **CTXM-04**: Context menu includes "Open With" submenu listing compatible applications
- [ ] **CTXM-05**: Context menu includes "Quick Look" to preview the file

### Quick Look

- [ ] **QLPV-01**: User can press spacebar to open Quick Look preview of selected image
- [ ] **QLPV-02**: User can press spacebar again or Escape to dismiss the preview
- [ ] **QLPV-03**: Quick Look shows the native floating QLPreviewPanel (not a sheet)

## Future Requirements

### Context Menu Enhancements

- **CTXM-06**: Services submenu in context menus
- **CTXM-07**: Copy Path to clipboard

### Quick Look Enhancements

- **QLPV-04**: Batch Quick Look cycling through multiple images

## Out of Scope

| Feature | Reason |
|---------|--------|
| FinderSync extension | Separate sandbox process; security-scoped access doesn't cross process boundaries |
| Move to Trash | Destructive file operation without undo; dangerous for training datasets |
| Smart quotes/dashes enabled | Corrupts LoRA training data tokens |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| EDIT-01 | Phase 7 | Pending |
| EDIT-02 | Phase 7 | Pending |
| EDIT-03 | Phase 7 | Pending |
| EDIT-04 | Phase 7 | Pending |
| EDIT-05 | Phase 7 | Pending |
| CTXM-01 | Phase 8 | Pending |
| CTXM-02 | Phase 8 | Pending |
| CTXM-03 | Phase 8 | Pending |
| CTXM-04 | Phase 8 | Pending |
| CTXM-05 | Phase 8 | Pending |
| QLPV-01 | Phase 9 | Pending |
| QLPV-02 | Phase 9 | Pending |
| QLPV-03 | Phase 9 | Pending |

**Coverage:**
- v1.4 requirements: 13 total
- Mapped to phases: 13
- Unmapped: 0

---
*Requirements defined: 2026-03-15*
*Last updated: 2026-03-15 — traceability populated after roadmap creation*
