# LoRA Dataset Browser

## Current State (Updated: 2025-12-20)

**Shipped:** v1.0 (working prototype)
**Status:** Internal use
**Users:** Solo developer (Rui)
**Feedback:** Functional but lacks directory navigation flexibility

**Codebase:**
- ~640 lines of Swift
- SwiftUI + AppKit (NSViewRepresentable for zoom/pan)
- MVVM architecture with @MainActor ViewModel
- Security-scoped bookmarks for sandbox compliance

**Current Capabilities:**
- Select a single directory containing image/caption pairs
- View images with pan and zoom (custom NSView)
- Edit caption text in a TextEditor
- Save captions with button click
- Auto-restore last directory on launch

**Known Issues:**
- No way to navigate between directories without re-selecting
- No visual indicator when caption has unsaved changes
- Save requires button click, not keyboard shortcut

## v1.1 Goals

**Vision:** Transform the app into a Finder-like dataset browser with native macOS polish.

**Motivation:**
- Current workflow requires re-selecting directories repeatedly
- Need faster navigation when reviewing large dataset collections
- Want the app to feel like a native Apple application

**Core Priority:** Directory navigation — the ability to freely browse folders in a sidebar tree.

**Scope (v1.1):**
- Sidebar with expandable folder tree (like Finder)
- Navigate directories without leaving the app
- Dirty indicator when caption text has unsaved changes
- Cmd+S keyboard shortcut to save (and File → Save menu)
- Native macOS look and feel — should feel Apple-made

**Success Criteria:**
- [ ] Can browse any folder hierarchy from sidebar tree
- [ ] Visual indicator shows when caption is modified but unsaved
- [ ] Cmd+S saves the current caption
- [ ] App looks and feels like a native macOS application

**Not Building (this version):**
- No batch operations (bulk editing, renaming, processing)
- No image editing (crop, rotate, resize)
- No AI/auto-captioning — purely manual editing

## Constraints

- **Platform**: macOS 14+ only — can use latest SwiftUI APIs
- **Dependencies**: Pure SwiftUI/AppKit — no external packages
- **Design**: Must look like a native Apple app (follow HIG)

## Open Questions

- [ ] How to handle security-scoped bookmarks when navigating to new directories?
- [ ] Should folder tree persist expansion state between sessions?
- [ ] Root folder for navigation — user-selected or home directory?

---

<details>
<summary>Original Vision (v1.0 - Archived)</summary>

## Vision

A macOS application for managing image-caption dataset pairs used for LoRA training. View images alongside their caption files and edit captions in place.

## Problem

Training LoRA models requires curated datasets with images and corresponding text prompts. Editing these manually via Finder + text editor is tedious. Need a unified view to see image and caption together.

## Success Criteria

- [x] View images with corresponding caption text
- [x] Edit caption text directly
- [x] Save captions to disk
- [x] Zoom and pan images
- [x] Persist directory selection across launches

## Scope

### Built
- Directory selection with NSOpenPanel
- Image/caption pairing by filename
- Zoomable/pannable image view
- Caption editing with TextEditor
- Security-scoped bookmarks for persistence

### Not Built
- Directory navigation (single folder only)
- Dirty indicator for unsaved changes
- Keyboard shortcuts for save

## Context

Built as a solo developer tool for personal LoRA training workflow.

## Constraints

- macOS only (uses AppKit integration)
- SwiftUI with NSViewRepresentable for advanced features

</details>

---
*Initialized: 2025-12-20*
