# LoRA Dataset Browser

## Current State (Updated: 2025-12-21)

**Shipped:** v1.1 Finder Navigation (2025-12-21)
**Status:** Internal use
**Users:** Solo developer (Rui)
**Feedback:** Gathering feedback on v1.1

**Codebase:**
- ~1,054 lines of Swift
- SwiftUI + AppKit (NSViewRepresentable for zoom/pan)
- MVVM architecture with @MainActor ViewModel
- Security-scoped bookmarks for sandbox compliance

**Current Capabilities:**
- Sidebar folder tree with expand/collapse navigation
- Navigate directories without re-selecting via NSOpenPanel
- View images with pan and zoom (custom NSView)
- Edit caption text in a TextEditor
- Cmd+S keyboard shortcut and File → Save menu
- Orange dirty indicator for unsaved changes
- Folder expansion state persists between app launches
- Auto-restore last directory on launch

**Known Issues:**
- None currently identified

## Next Milestone Goals

_No active milestone planned. Gathering feedback on v1.1._

---

<details>
<summary>v1.1 Goals (Archived)</summary>

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
- [x] Can browse any folder hierarchy from sidebar tree
- [x] Visual indicator shows when caption is modified but unsaved
- [x] Cmd+S saves the current caption
- [x] App looks and feels like a native macOS application

</details>

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
