# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a macOS SwiftUI application for managing image-caption dataset pairs, typically used for LoRA (Low-Rank Adaptation) training datasets. The app allows users to view images alongside their caption files and edit captions in place.

## Building and Running

This is an Xcode project for macOS. To build and run:

```bash
# Open in Xcode
open lora-dataset/lora-dataset.xcodeproj

# Build from command line (if needed)
xcodebuild -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset build

# Run tests
xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset
```

## Architecture

### Core Components

**DatasetViewModel** (`DatasetViewModel.swift`)
- Main business logic and state management
- Handles directory selection with security-scoped bookmarks for persistent access across app launches
- Scans directories for image/caption pairs (supported image formats: jpg, jpeg, png, webp, bmp, tiff)
- Matches images with corresponding `.txt` or `.caption` files based on filename
- Manages saving captions back to disk with proper security-scoped resource access
- Uses `withScopedDirectoryAccess()` helper to properly manage security-scoped resource lifecycle

**ImageCaptionPair** (`ImageCaptionPair.swift`)
- Data model representing an image and its associated caption file
- Uses UUID for identity, enabling proper List selection in SwiftUI
- Mutable `captionText` allows in-place editing

**ContentView** (`ContentView.swift`)
- Main UI with NavigationSplitView: sidebar shows image list, detail shows selected image + caption editor
- Manages local state for image display (`loadedImage`, `imageScale`, `imageOffset`)
- Resets zoom/pan when switching between images via `onChange(of: vm.selectedID)`
- Uses HSplitView to provide resizable image/caption editing panes

**ZoomablePannableImage** (`ZoomablePannableImage.swift`)
- Custom NSViewRepresentable wrapping ZoomableImageNSView
- Provides zoom (mouse wheel) and pan (click-drag) functionality
- Auto-fits images to available space on load with `resetToFit()`
- Uses coordinator pattern to sync state between NSView and SwiftUI bindings
- Implements `isUpdatingProgrammatically` flag to prevent feedback loops when syncing state

### Key Technical Details

**Security-Scoped Bookmarks**
- macOS sandboxing requires security-scoped bookmarks for persistent folder access
- Bookmarks are created when user selects a folder and stored in UserDefaults
- The app resolves bookmarks on startup to restore the last-used directory
- All file operations wrap security-scoped resource access using `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`

**File Pairing Logic**
- The app scans a directory and pairs each image with a caption file having the same base filename
- If no caption file exists, it creates a reference to `{basename}.txt` (created on first save)
- Caption files can have `.txt` or `.caption` extensions

**Image Display**
- Images are loaded as NSImage and displayed in a custom zoomable/pannable view
- Zoom is centered on mouse cursor position during scroll wheel events
- The view auto-resets to "fit" mode when switching images or resizing the view significantly

**State Synchronization**
- ZoomablePannableImage uses bindings for `scale` and `offset` that sync bidirectionally with ContentView state
- Care is taken to avoid update loops using tolerance checks and the `isUpdatingProgrammatically` flag

## Development Notes

**Debugging**
- System logs are suppressed in DEBUG mode (see `lora_datasetApp.swift` init)
- Console prints are used for debugging file operations (look for `[saveSelected]` prefix)

**macOS Specifics**
- This is a macOS-only app using AppKit (NSImage, NSOpenPanel, NSView)
- Target platform is macOS with SwiftUI lifecycle
