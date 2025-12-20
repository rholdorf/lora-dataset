# Coding Conventions

**Analysis Date:** 2025-12-20

## Naming Patterns

**Files:**
- PascalCase for Swift source files: `ContentView.swift`, `DatasetViewModel.swift`, `ImageCaptionPair.swift`, `ZoomablePannableImage.swift`
- snake_case for app entry and tests: `lora_datasetApp.swift`, `lora_datasetTests.swift`, `lora_datasetUITests.swift`

**Functions:**
- camelCase for all functions: `chooseDirectory()`, `scanDirectory()`, `saveSelected()`, `reloadCaptionForSelected()`, `resetToFit()`
- No special prefix for async functions (just use async keyword)
- Event handlers follow AppKit naming: `scrollWheel()`, `mouseDown()`, `mouseDragged()`, `mouseUp()`

**Variables:**
- camelCase for variables: `imageScale`, `imageOffset`, `loadedImage`, `captionText`, `selectedID`
- camelCase for properties: `pairs`, `directoryURL`, `securedDirectoryURL`, `supportedImageExtensions`
- No underscore prefix for private properties

**Types:**
- PascalCase for structs/classes: `DatasetViewModel`, `ImageCaptionPair`, `ContentView`, `ZoomablePannableImage`, `ZoomableImageNSView`
- Descriptive suffixes: `ViewModel` for view models, `View` implicit for SwiftUI views, `NSView` for AppKit views
- Protocols: PascalCase (inherited from Swift stdlib: `Identifiable`, `Hashable`, `ObservableObject`, `View`)

## Code Style

**Formatting:**
- Indentation: 4 spaces (no tabs)
- Line length: No strict limit, generally reasonable (~80-120 characters)
- Quotes: Double quotes for strings (Swift standard)
- Semicolons: Not used (Swift standard)
- Bracket style: Opening brace on same line

**Access Control:**
- Default: Internal (no modifier when not specified)
- Private: Used extensively for implementation details (`private var`, `private func`)
- Public: Minimal, only for public APIs (`public func resetToFit()`)
- Final: Used on concrete classes (`final class ZoomableImageNSView`, `final class lora_datasetUITests`)

**Property Wrappers:**
- `@Published` - Observable properties in ViewModels (`var pairs`, `var selectedID`)
- `@State` - Local view state, always private (`@State private var imageScale`)
- `@StateObject` - ViewModel ownership in views (`@StateObject var vm`)
- `@Binding` - Two-way bindings for child views
- `@MainActor` - Thread safety for ViewModels

## Import Organization

**Order:**
1. Foundation framework (for FileManager, URL)
2. SwiftUI framework (for UI components)
3. AppKit framework (for NSImage, NSView, NSOpenPanel)
4. Testing frameworks (Testing, XCTest) in test files

**Grouping:**
- No blank lines between imports (standard Swift style)
- Alphabetical within groups not enforced

**Path Aliases:**
- No custom path aliases (not applicable to Swift/Xcode projects)

## Error Handling

**Patterns:**
- Optional try with nil coalescing: `(try? String(contentsOf: url)) ?? ""`
- No explicit catch blocks currently
- Silent failures with fallback values
- Console logging for debugging in DEBUG mode

**Error Types:**
- Standard Swift Error protocol (no custom error types defined)
- Errors not propagated to users (no error dialogs)

**Async:**
- Uses async/await with Task wrappers: `Task { await vm.chooseDirectory() }`
- No explicit error throwing in async functions currently

## Logging

**Framework:**
- Console print statements
- System logs suppressed in DEBUG: `setenv("OS_ACTIVITY_MODE", "disable", 1)`

**Patterns:**
- Prefixed messages: `print("[saveSelected] ...")` for file operations
- Mostly Portuguese log messages
- No structured logging framework

## Comments

**When to Comment:**
- File headers with standard Xcode template (creator, date)
- Complex logic explanation (tolerance checks, coordinate transformations)
- Business rule documentation (security-scoped resource lifecycle)
- Portuguese comments for implementation notes

**Doc Comments:**
- `///` for struct/class documentation
- Example: `/// Uma view SwiftUI que dá zoom com roda do mouse e pan com arraste.`
- Minimal usage (only 2-3 instances in entire codebase)

**TODO Comments:**
- Not detected in codebase
- No TODO/FIXME/HACK markers found

## Function Design

**Size:**
- Generally concise (most functions under 30 lines)
- Largest function: `draw()` in ZoomableImageNSView (~32 lines)
- Helper functions extracted where appropriate

**Parameters:**
- Generally 0-2 parameters
- Generics used sparingly: `withScopedDirectoryAccess<T>(_:)`
- No explicit parameter limits enforced

**Return Values:**
- Explicit return types always specified
- Early returns used in guard statements
- Optional returns when operation can fail: `func reloadCaptionForSelected() -> String?`

## Module Design

**Exports:**
- Internal by default (no explicit module exports)
- No barrel files (not applicable to Swift)
- Everything in same target compiles together

**File Organization:**
- One primary type per file
- Nested types allowed (Coordinator inside ZoomablePannableImage)
- No circular dependencies

## SwiftUI-Specific Patterns

**View Composition:**
- Small, focused views
- Extract subviews for clarity
- Use @ViewBuilder implicitly

**State Management:**
- @StateObject for owned ViewModels
- @State for local view state (always private)
- @Published in ViewModels for observable state
- Custom Bindings for computed state

**Property Wrappers Order:**
- Ownership wrappers first (@StateObject, @ObservedObject)
- State second (@State)
- Environment third (not used in this project)

## AppKit Integration

**NSViewRepresentable:**
- Coordinator pattern for state bridging
- `makeNSView()`, `updateNSView()`, `makeCoordinator()` protocol methods
- Weak references to prevent retain cycles: `weak var coordinator`

**NSView Subclasses:**
- Override necessary event handlers: `scrollWheel()`, `mouseDown()`, `draw()`
- Call super when appropriate
- Use `setNeedsDisplay()` for redraw triggering

---

*Convention analysis: 2025-12-20*
*Update when patterns change*
