# Codebase Concerns

**Analysis Date:** 2025-12-20

## Tech Debt

**Security-Scoped Resource Lifecycle Violation:**
- Issue: File operations performed outside security-scoped resource access blocks
- Files: `DatasetViewModel.swift:144` and `DatasetViewModel.swift:191`
- Why: Code structure has file existence checks before entering scope wrapper
- Impact: Violates macOS sandboxing requirements, could cause access denied errors
- Fix approach: Move `FileManager.default.fileExists()` calls inside `withScopedDirectoryAccess()` wrapper

**Duplicate File Reading Pattern:**
- Issue: Identical `(try? String(contentsOf: url)) ?? ""` pattern appears twice
- Files: `DatasetViewModel.swift:145` and `DatasetViewModel.swift:192`
- Why: No extraction into helper function
- Impact: Code duplication, harder to maintain/update error handling
- Fix approach: Extract into `private func readCaptionFile(from url: URL) -> String`

**Duplicate Bookmark Code:**
- Issue: Bookmark creation and resolution code duplicated across three methods
- Files: `DatasetViewModel.swift:39-42`, `52-56`, `84-87`
- Why: Rapid development without refactoring
- Impact: Harder to maintain, potential for inconsistency
- Fix approach: Extract bookmark operations into separate helper methods

**State Synchronization Complexity:**
- Issue: Complex bidirectional binding with tolerance checks and `isUpdatingProgrammatically` flag
- Files: `ZoomablePannableImage.swift:53-64`, `22-30`, `92`
- Why: Preventing feedback loops between SwiftUI and NSView requires careful state management
- Impact: Hard to verify correctness, subtle bugs possible
- Fix approach: Consider unidirectional data flow or reactive framework

**Custom Binding Mutation:**
- Issue: Direct array mutation through custom Binding bypasses SwiftUI tracking
- Files: `ContentView.swift:79-82`
- Why: Convenience for in-place caption editing
- Impact: Could cause SwiftUI to miss updates, unpredictable re-rendering
- Fix approach: Use proper state management with explicit mutation methods

## Known Bugs

**Stale Bookmark Used Without Recovery:**
- Symptoms: App uses stale security-scoped bookmark without user notification
- Trigger: Bookmark resolution returns stale bookmark warning
- Files: `DatasetViewModel.swift:89-91`
- Workaround: None - warning only printed to console
- Root cause: No fallback to prompt user for directory re-selection
- Fix: Add user-facing alert and prompt to re-select directory

**Image Loading Fails Silently:**
- Symptoms: "Não foi possível carregar a imagem" displayed with no error details
- Trigger: Corrupted image file, unsupported format, or file deleted
- Files: `ContentView.swift:112-119`
- Workaround: User must guess what went wrong
- Root cause: No error handling or validation on `NSImage(contentsOf:)`
- Fix: Add error handling with specific error messages (file not found, corrupted, unsupported format)

**Race Condition in Array Updates:**
- Symptoms: Potential crash if pairs array modified while UI renders selection
- Trigger: Fast directory changes or file operations during UI updates
- Files: `ContentView.swift:44-45`, `110-111`
- Workaround: None currently
- Root cause: Index lookups not validated between async operations
- Fix: Add bounds checking or use UUID-based lookups instead of indices

**Security-Scoped Access Continues on Failure:**
- Symptoms: If `startAccessingSecurityScopedResource()` returns false, defer still calls stop
- Trigger: Insufficient permissions or sandbox denial
- Files: `DatasetViewModel.swift:104-113`
- Workaround: None - error hidden
- Root cause: No check of startAccessing return value
- Fix: Store result and only call stop if start succeeded

## Security Considerations

**File Operations Outside Sandbox Scope:**
- Risk: File existence checks performed before acquiring security-scoped access
- Files: `DatasetViewModel.swift:144`, `191`
- Current mitigation: None - violates sandbox model
- Recommendations: Move all file operations inside `withScopedDirectoryAccess()` wrapper

**Fallback to Unsecured URL:**
- Risk: If bookmark resolution fails, code falls back to plain URL without security scope
- Files: `DatasetViewModel.swift:71`
- Current mitigation: None - bypasses sandboxing
- Recommendations: Fail gracefully with user prompt instead of unsecured access

**No Input Validation on Caption Text:**
- Risk: Arbitrary string written to disk without validation
- Files: `DatasetViewModel.swift:173-175`
- Current mitigation: Swift String type safety only
- Recommendations: Low priority - file system is already sandboxed

## Performance Bottlenecks

**Synchronous Image Loading on Main Thread:**
- Problem: `NSImage(contentsOf:)` blocks main thread during image selection
- Files: `ContentView.swift:112, 117`
- Measurement: Noticeable delay with large images (>5MB)
- Cause: Synchronous file I/O on main thread
- Improvement path: Load images asynchronously with Task/async-await

**Synchronous Directory Scanning:**
- Problem: `scanDirectory()` is async but performs blocking file operations
- Files: `DatasetViewModel.swift:118, 144, 145`
- Measurement: Delays with large directories (>1000 files)
- Cause: `contentsOfDirectory()`, `fileExists()`, `String(contentsOf:)` are synchronous
- Improvement path: Use async file operations or dispatch to background queue

**No Image Caching:**
- Problem: Same image reloaded every time user switches back to it
- Files: `ContentView.swift:112`
- Measurement: Repeated disk reads for same images
- Cause: No caching layer
- Improvement path: Add NSCache for recently viewed images

## Fragile Areas

**ZoomablePannableImage State Synchronization:**
- Files: `ZoomablePannableImage.swift` (entire file, 262 lines)
- Why fragile: Complex bidirectional binding between SwiftUI and NSView with tolerance checks
- Common failures: State desync causing jumpy zoom, feedback loops
- Safe modification: Test thoroughly with various scale/offset combinations before changing
- Test coverage: None - no tests for this component

**Security-Scoped Bookmark Lifecycle:**
- Files: `DatasetViewModel.swift:39-72, 79-99, 101-113`
- Why fragile: Manual resource management with start/stop calls
- Common failures: Resource leaks if defer doesn't execute, access denied if scope not held
- Safe modification: Ensure all file operations wrapped in `withScopedDirectoryAccess()`
- Test coverage: None - no tests for bookmark handling

**Custom Binding for Array Mutation:**
- Files: `ContentView.swift:79-82`
- Why fragile: Direct mutation bypasses SwiftUI state tracking
- Common failures: UI not refreshing after caption edits
- Safe modification: Consider using proper ViewModel methods instead
- Test coverage: None

## Scaling Limits

**Large Directories:**
- Current capacity: Works well with <500 image pairs
- Limit: ~1000-2000 pairs before UI becomes sluggish
- Symptoms at limit: Slow directory scanning, lag when scrolling sidebar
- Scaling path: Implement pagination or virtual scrolling in List

**Large Image Files:**
- Current capacity: Works with images up to ~10MB
- Limit: High-resolution images (>50MB) cause UI freezes
- Symptoms at limit: Frozen UI during image load
- Scaling path: Async loading, thumbnail generation, lazy loading

## Dependencies at Risk

**Swift 5.0:**
- Risk: Older Swift version, modern features missing
- Impact: Cannot use latest Swift language features
- Migration plan: Upgrade to Swift 5.9+ for better concurrency support

**macOS 15.5 Deployment Target:**
- Risk: Limits market to newest macOS only
- Impact: Users on older macOS cannot run app
- Migration plan: Consider lowering to macOS 14 for wider compatibility

## Missing Critical Features

**Error Reporting to Users:**
- Problem: All errors logged to console, no user-facing dialogs
- Current workaround: Users have no visibility into failures
- Blocks: Cannot debug issues without checking console
- Implementation complexity: Low - add NSAlert for critical errors

**Undo/Redo for Caption Edits:**
- Problem: No undo functionality when editing captions
- Current workaround: Manual reversion required
- Blocks: Accidental edits cannot be undone
- Implementation complexity: Medium - integrate with NSUndoManager

**Bulk Operations:**
- Problem: Cannot save all captions at once, only selected pair
- Current workaround: Manual save for each pair
- Blocks: Inefficient workflow for batch editing
- Implementation complexity: Low - add "Save All" button

**Keyboard Shortcuts:**
- Problem: No keyboard navigation (⌘S to save, arrow keys for navigation)
- Current workaround: Mouse-only workflow
- Blocks: Slower editing workflow
- Implementation complexity: Low - add .keyboardShortcut() modifiers

## Test Coverage Gaps

**ViewModel Business Logic:**
- What's not tested: All core functions in `DatasetViewModel.swift`
- Risk: File operations, bookmark handling could break silently
- Priority: High
- Difficulty to test: Medium - requires mocking FileManager and UserDefaults

**File Pairing Algorithm:**
- What's not tested: `scanDirectory()` logic for matching images to captions
- Risk: Wrong pairings or missing files undetected
- Priority: High
- Difficulty to test: Medium - requires test fixture files

**Security-Scoped Resource Handling:**
- What's not tested: Bookmark creation, restoration, scope lifecycle
- Risk: Access violations or resource leaks
- Priority: High
- Difficulty to test: Hard - requires sandbox environment simulation

**Custom View Components:**
- What's not tested: ZoomablePannableImage zoom/pan logic
- Risk: UI bugs in image viewer
- Priority: Medium
- Difficulty to test: Hard - requires UI testing with precise mouse events

**Error Paths:**
- What's not tested: Failure cases (corrupted files, permission denied, etc.)
- Risk: App crashes or hangs on errors
- Priority: High
- Difficulty to test: Medium - requires error injection

---

*Concerns audit: 2025-12-20*
*Update as issues are fixed or new ones discovered*
