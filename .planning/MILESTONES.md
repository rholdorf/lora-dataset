# Project Milestones: LoRA Dataset Browser

## v1.4 Native OS Integration (Shipped: 2026-03-16)

**Delivered:** Deep macOS integration with native text editing, Finder context menus, and Quick Look preview — the app now feels like a first-party Apple tool.

**Phases completed:** 7-9 (3 plans total)

**Key accomplishments:**

- Native NSTextView caption editor with spell check, grammar check, dictionary lookup, and LoRA-safe settings
- Right-click context menus on sidebar files (Reveal in Finder, Open With, Quick Look) and folders (Open in Finder, Open in Terminal)
- Spacebar Quick Look toggle with arrow key navigation while panel is open
- Async image loading for smooth keyboard navigation

**Stats:**

- 1,639 lines of Swift
- 3 phases, 3 plans, ~8 tasks
- 2 days (2026-03-15 → 2026-03-16)

**Git range:** `feat(07-01)` → `feat: add spacebar Quick Look toggle`

---

## v1.1 Finder Navigation (Shipped: 2025-12-21)

**Delivered:** Transformed the app from a single-directory viewer into a Finder-like dataset browser with sidebar folder tree, save shortcuts, and native macOS polish.

**Phases completed:** 1-4 (5 plans total)

**Key accomplishments:**

- Folder tree navigation with expand/collapse in sidebar
- Cmd+S keyboard shortcut with File → Save menu integration
- Orange dirty indicator showing unsaved caption changes
- Folder expansion state persists between app restarts
- Native macOS look with Finder-like folder styling and manual disclosure controls

**Stats:**

- 4 files created/modified
- 1,054 lines of Swift
- 4 phases, 5 plans, ~14 tasks
- 2 days from start to ship (2025-12-20 → 2025-12-21)

**Git range:** `feat(01-01)` → `feat(04-01)`

**What's next:** TBD - gathering feedback on v1.1

---
