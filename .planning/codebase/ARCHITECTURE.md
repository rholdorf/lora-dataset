# Architecture

**Analysis Date:** 2025-12-20

## Pattern Overview

**Overall:** MVVM (Model-View-ViewModel) with SwiftUI + AppKit Integration

**Key Characteristics:**
- Native macOS application using SwiftUI for UI and AppKit for advanced features
- Observable state management with @Published properties
- Security-scoped resource pattern for macOS sandbox compliance
- Custom NSViewRepresentable for advanced image manipulation
- Single-target monolithic architecture

## Layers

**View Layer:**
- Purpose: UI presentation and user interaction
- Contains: SwiftUI views, NSViewRepresentable wrappers
- Depends on: ViewModel for state, AppKit for native components
- Used by: User interactions
- Files:
  - `lora_datasetApp.swift` - App entry point with @main
  - `ContentView.swift` - Main UI with NavigationSplitView
  - `ZoomablePannableImage.swift` - Custom NSViewRepresentable for image viewing

**ViewModel Layer:**
- Purpose: State management and business logic
- Contains: Observable state, file operations, security-scoped access
- Depends on: Model layer, Foundation framework
- Used by: Views via @StateObject binding
- Files:
  - `DatasetViewModel.swift` - Centralized state with @MainActor

**Model Layer:**
- Purpose: Data structures and domain logic
- Contains: Identifiable structs, data models
- Depends on: Foundation only
- Used by: ViewModel and Views
- Files:
  - `ImageCaptionPair.swift` - Image-caption association model

**Utility/Bridge Layer:**
- Purpose: SwiftUI-to-AppKit integration
- Contains: Coordinator pattern, NSView subclasses
- Depends on: AppKit, SwiftUI
- Used by: SwiftUI views via NSViewRepresentable
- Files:
  - `ZoomablePannableImage.swift` - Contains Coordinator and ZoomableImageNSView

## Data Flow

**Application Startup:**

1. `lora_datasetApp` initializes with @main entry point
2. Suppresses system logs in DEBUG mode
3. Creates `ContentView` with @StateObject `DatasetViewModel`
4. ViewModel attempts to restore previous directory from UserDefaults bookmark
5. If bookmark exists and valid, automatically scans directory and populates pairs

**Directory Selection Flow:**

1. User clicks "Escolher Pasta" button in ContentView
2. `vm.chooseDirectory()` called (async)
3. NSOpenPanel displays folder picker
4. User selects folder
5. Security-scoped bookmark created and saved to UserDefaults
6. `vm.scanDirectory()` scans for image-caption pairs
7. `@Published pairs` array updated
8. ContentView sidebar refreshes automatically

**Caption Editing Flow:**

1. User selects image-caption pair from sidebar list
2. `vm.selectedID` updates, triggering onChange in ContentView
3. Image loaded via `NSImage(contentsOf:)` into local @State
4. Caption text displayed in TextEditor via Binding
5. User edits caption in TextEditor
6. Binding mutates `vm.pairs[index].captionText` directly
7. User clicks "Salvar" button
8. `vm.saveSelected()` writes caption to disk with security-scoped access
9. Verification read confirms persistence

**Image Display and Interaction:**

1. User selects pair, triggering image load in ContentView
2. NSImage loaded and passed to ZoomablePannableImage via binding
3. ZoomablePannableImage creates ZoomableImageNSView (NSView)
4. View calls `resetToFit()` to auto-scale image to viewport
5. User scrolls mouse wheel → `scrollWheel()` event in NSView
6. Scale and offset calculations performed
7. Coordinator updates SwiftUI bindings via `notifyChanges()`
8. ContentView state synced, preventing feedback loops with tolerance checks
9. View redraws with new transform via `draw()` method

**State Management:**
- Centralized in DatasetViewModel with @Published properties
- Unidirectional data flow from ViewModel to Views
- Bidirectional bindings for image zoom/pan state with tolerance guards

## Key Abstractions

**DatasetViewModel:**
- Purpose: Single source of truth for app state
- Pattern: ObservableObject with @MainActor
- Location: `DatasetViewModel.swift`
- Key properties: `pairs`, `selectedID`, `directoryURL`, `securedDirectoryURL`
- Methods: `chooseDirectory()`, `scanDirectory()`, `saveSelected()`, `reloadCaptionForSelected()`

**ImageCaptionPair:**
- Purpose: Represent image-caption association
- Pattern: Identifiable struct with UUID
- Location: `ImageCaptionPair.swift`
- Properties: `id`, `imageURL`, `captionURL`, `captionText`

**Security-Scoped Access Wrapper:**
- Purpose: Ensure proper sandbox resource lifecycle
- Pattern: Generic rethrows wrapper with defer cleanup
- Location: `DatasetViewModel.swift:101-113`
- Method: `withScopedDirectoryAccess<T>(_:)`

**NSViewRepresentable + Coordinator:**
- Purpose: Bridge SwiftUI bindings to AppKit NSView
- Pattern: Coordinator pattern for state synchronization
- Location: `ZoomablePannableImage.swift`
- Components:
  - `ZoomablePannableImage` struct (SwiftUI wrapper)
  - `Coordinator` class (state bridge with weak reference)
  - `ZoomableImageNSView` (NSView implementation)

**Tolerance-Based State Sync:**
- Purpose: Prevent infinite update loops between SwiftUI and NSView
- Pattern: Threshold-based update guards
- Location: `ZoomablePannableImage.swift:22-30, 55-61`
- Tolerances: Scale ±0.001, Offset ±0.1 pixels
- Flag: `isUpdatingProgrammatically` to prevent callback loops

## Entry Points

**Application Entry:**
- Location: `lora_datasetApp.swift:10-26`
- Triggers: macOS app launch
- Responsibilities: Initialize app, suppress debug logs, create root ContentView

**Main UI View:**
- Location: `ContentView.swift:4-124`
- Triggers: Created by app entry point
- Responsibilities: NavigationSplitView layout, image/caption display, user interactions

**ViewModel Initialization:**
- Location: `DatasetViewModel.swift` (init called via @StateObject)
- Triggers: ContentView creation
- Responsibilities: Restore previous directory bookmark if available

## Error Handling

**Strategy:** Defensive programming with optional chaining and nil coalescing

**Patterns:**
- Optional try (`try?`) for file operations with fallback to empty string
- `guard let` for unwrapping with early return
- Silent failures with console logging (DEBUG mode)
- No user-facing error dialogs currently implemented

**Examples:**
- Caption read: `(try? String(contentsOf: url)) ?? ""` - `DatasetViewModel.swift:145, 192`
- Bookmark resolution: Falls back to nil on failure - `DatasetViewModel.swift:88`
- Image loading: Displays "Não foi possível carregar a imagem" on nil - `ContentView.swift:116`

## Cross-Cutting Concerns

**Logging:**
- Console.print for file operations with `[saveSelected]` prefix
- System logs suppressed in DEBUG via `setenv("OS_ACTIVITY_MODE", "disable", 1)`
- Location: `lora_datasetApp.swift:13-18`

**Thread Safety:**
- `@MainActor` on DatasetViewModel ensures UI updates on main thread
- Async/await for file operations
- `@State` and `@Published` provide automatic thread-safe updates

**File Access Security:**
- Security-scoped bookmarks for persistent folder access
- All file operations wrapped with `startAccessingSecurityScopedResource()`/`stopAccessingSecurityScopedResource()`
- Bookmarks saved to UserDefaults with key "securedDirectoryBookmark"
- Location: `DatasetViewModel.swift:39-72, 101-113`

**Resource Management:**
- Defer blocks ensure security-scoped resource cleanup
- Weak references in Coordinator prevent retain cycles
- NSView cleanup via `removeFromSuperview()` pattern

---

*Architecture analysis: 2025-12-20*
*Update when major patterns change*
