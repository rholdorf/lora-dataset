# LoRA Dataset Browser

## Current State (Updated: 2026-03-16)

**Shipped:** v1.4 Native OS Integration (2026-03-16)
**Status:** Internal use
**Users:** Solo developer (Rui)

**Codebase:**
- ~1,639 lines of Swift
- SwiftUI + AppKit (NSViewRepresentable for zoom/pan, NSTextView for caption editing)
- MVVM architecture with @MainActor ViewModel
- Security-scoped bookmarks for sandbox compliance
- macOS 14+ deployment target

**Current Capabilities:**
- Native macOS toolbar with folder picker and path display
- Sidebar folder tree with expand/collapse navigation
- Navigate directories without re-selecting via NSOpenPanel
- View images with pan and zoom (custom NSView)
- Edit captions in native NSTextView with spell check, grammar check, dictionary lookup
- LoRA-safe text settings (no smart quotes/dashes)
- Right-click context menus: Reveal in Finder, Open With, Quick Look (files); Open in Finder, Open in Terminal (folders)
- Spacebar Quick Look toggle with arrow key navigation while panel is open
- Async image loading for smooth keyboard navigation
- File menu: Open Folder (Cmd+O), Save (Cmd+S), Reload Caption (Cmd+Shift+R)
- Orange dirty indicator for unsaved changes
- Folder expansion state persists between app launches
- Session restoration: remembers last folder and selected image

**Known Issues:**
- None currently identified

---

<details>
<summary>v1.4 Goals (Archived)</summary>

**Goal:** Deep macOS integration — Finder context menus, Quick Look preview, and full native text editing with spell check and dictionary support.

**Target features:**
- Finder-native context menu (right-click) on files and folders in sidebar
- Quick Look preview on spacebar press
- Full native NSTextView for caption editing (spell check, grammar, dictionary, auto-language detection, substitutions)

**Success Criteria:**
- [x] Native NSTextView caption editor with spell/grammar check and LoRA-safe settings
- [x] Right-click context menus on files and folders in sidebar
- [x] Spacebar Quick Look toggle with floating QLPreviewPanel
- [x] Arrow key navigation while Quick Look panel is open

</details>

<details>
<summary>v1.3 Goals (Archived)</summary>

**Vision:** Session restoration to remember last viewed position.

**Motivation:**
- Users should return to exactly where they left off
- No need to re-navigate to the same folder and image

**Scope (v1.3):**
- Remember last viewed folder path
- Remember last selected image
- Auto-scroll to restored image in file list

**Success Criteria:**
- [x] App remembers folder and image selection across launches
- [x] File list scrolls to show restored selection

</details>

<details>
<summary>v1.2 Goals (Archived)</summary>

**Vision:** UI polish with native macOS toolbar integration.

**Motivation:**
- Inline buttons looked non-native
- Wanted proper macOS toolbar appearance
- Need keyboard shortcuts for common actions

**Scope (v1.2):**
- Native macOS toolbar with folder picker and path display
- Save and Reload buttons in toolbar
- File menu commands with keyboard shortcuts

**Success Criteria:**
- [x] Controls in native toolbar, not inline
- [x] File menu with keyboard shortcuts (Cmd+O, Cmd+S, Cmd+Shift+R)
- [x] Clean, Finder-like appearance

</details>

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
*Last updated: 2026-03-16 after v1.4 milestone*
