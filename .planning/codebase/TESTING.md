# Testing Patterns

**Analysis Date:** 2025-12-20

## Test Framework

**Runner:**
- Swift Testing framework (Apple's modern testing framework)
- XCTest for UI tests
- Config: Integrated into Xcode project configuration

**Assertion Library:**
- Swift Testing: `#expect(...)` for modern tests
- XCTest: `XCTAssert...` family for UI tests

**Run Commands:**
```bash
# From Xcode
Product → Test (⌘U)

# From command line
xcodebuild test -project lora-dataset.xcodeproj -scheme lora-dataset

# Run specific test
xcodebuild test -project lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests/lora_datasetTests
```

## Test File Organization

**Location:**
- Unit tests: `lora-datasetTests/` directory (separate from source)
- UI tests: `lora-datasetUITests/` directory (separate from source)
- Not co-located with source files (Xcode standard pattern)

**Naming:**
- Unit test files: `{ProjectName}Tests.swift` (snake_case matching app name)
- UI test files: `{ProjectName}UITests.swift`, `{ProjectName}UITestsLaunchTests.swift`
- Test classes: `struct lora_datasetTests`, `final class lora_datasetUITests`

**Structure:**
```
lora-dataset/
├── lora-dataset/           # Source code
├── lora-datasetTests/      # Unit tests
│   └── lora_datasetTests.swift
└── lora-datasetUITests/    # UI tests
    ├── lora_datasetUITests.swift
    └── lora_datasetUITestsLaunchTests.swift
```

## Test Structure

**Suite Organization (Swift Testing):**
```swift
import Testing

struct lora_datasetTests {
    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }
}
```

**Suite Organization (XCTest):**
```swift
import XCTest

final class lora_datasetUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }
}
```

**Patterns:**
- Swift Testing: Uses `@Test` attribute instead of `func test...` prefix
- XCTest: Traditional `func testXXX()` naming
- Setup/teardown: `setUpWithError()`, `tearDownWithError()` for XCTest
- Async support: `async throws` built into both frameworks
- Thread safety: `@MainActor` for UI tests

## Mocking

**Framework:**
- No mocking framework detected
- Standard Swift protocol-based mocking would be used if needed

**Patterns:**
- Not currently implemented
- Would likely use protocol abstraction for FileManager, UserDefaults

**What to Mock:**
- File system operations (FileManager)
- UserDefaults for bookmark storage
- NSOpenPanel for folder selection
- Image loading operations

**What NOT to Mock:**
- Pure functions
- SwiftUI view rendering
- Simple data models

## Fixtures and Factories

**Test Data:**
- No test fixtures or factories currently implemented
- Would create in test files when needed

**Potential Patterns:**
```swift
// Future factory pattern example
func createTestImageCaptionPair(
    imageURL: URL = URL(fileURLWithPath: "/test/image.jpg"),
    captionURL: URL = URL(fileURLWithPath: "/test/image.txt"),
    captionText: String = "Test caption"
) -> ImageCaptionPair {
    ImageCaptionPair(
        imageURL: imageURL,
        captionURL: captionURL,
        captionText: captionText
    )
}
```

**Location:**
- Would create in test files themselves
- No separate fixtures directory yet

## Coverage

**Requirements:**
- No enforced coverage target
- Coverage tracking available via Xcode

**Configuration:**
- Built into Xcode test runner
- No separate coverage tool

**View Coverage:**
```bash
# Enable code coverage in Xcode scheme settings
# View report: Product → Show Code Coverage (⌘⇧9)

# Command line
xcodebuild test -project lora-dataset.xcodeproj -scheme lora-dataset -enableCodeCoverage YES
```

**Current Status:**
- Minimal coverage (only placeholder tests exist)
- No tests for core business logic yet

## Test Types

**Unit Tests:**
- Framework: Swift Testing
- Scope: Test individual functions/structs in isolation
- Mocking: Would mock file system and external dependencies
- Current status: Only placeholder test exists
- File: `lora_datasetTests.swift`

**UI Tests:**
- Framework: XCTest with XCUIApplication
- Scope: Test user interactions and UI state
- Current implementation:
  - `testExample()` - Basic app launch test
  - `testLaunchPerformance()` - Launch time measurement
- Files: `lora_datasetUITests.swift`, `lora_datasetUITestsLaunchTests.swift`

**Integration Tests:**
- Not separately defined
- Would be implemented as unit tests that test multiple components together

**Performance Tests:**
- XCTest `measure()` used for launch performance
- Example: `measure(metrics: [XCTApplicationLaunchMetric()]) { ... }`

## Common Patterns

**Async Testing (Swift Testing):**
```swift
@Test func asyncExample() async throws {
    // Async code naturally supported
    let result = await someAsyncFunction()
    #expect(result == expectedValue)
}
```

**Async Testing (XCTest):**
```swift
@MainActor
func testAsyncOperation() async throws {
    let result = await viewModel.scanDirectory()
    XCTAssertNotNil(result)
}
```

**Error Testing:**
```swift
// Swift Testing
@Test func throwsError() throws {
    #expect(throws: SomeError.self) {
        try functionThatThrows()
    }
}

// XCTest
func testThrows() {
    XCTAssertThrowsError(try functionThatThrows())
}
```

**UI Testing:**
```swift
@MainActor
func testUIInteraction() throws {
    let app = XCUIApplication()
    app.launch()

    // Example: Click button, verify state
    app.buttons["Escolher Pasta"].tap()
    // Add assertions
}
```

**Launch Testing:**
```swift
final class lora_datasetUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
```

**Screenshot Testing:**
- Launch tests capture screenshots automatically
- Screenshots attached with `XCTAttachment`
- Lifetime: `.keepAlways` for permanent storage

## Testing Best Practices Observed

- Use of `final class` for test classes (prevents subclassing)
- `@MainActor` annotation for thread safety in UI tests
- `continueAfterFailure = false` for fast-fail behavior
- Performance metrics tracking with XCTest
- Async/await native support in both frameworks

## Current Test Coverage Gaps

**Untested Areas:**
- `DatasetViewModel.swift` - No tests for business logic
  - `chooseDirectory()` not tested
  - `scanDirectory()` not tested
  - `saveSelected()` not tested
  - Bookmark persistence not tested
- `ImageCaptionPair.swift` - No model tests
- `ContentView.swift` - No view tests
- `ZoomablePannableImage.swift` - No custom view tests
- Security-scoped resource handling not tested
- File pairing logic not tested
- Error handling paths not tested

**Priority for Testing:**
- High: ViewModel business logic (file operations, bookmark handling)
- Medium: Image-caption pairing algorithm
- Low: UI interactions (already have launch tests)

---

*Testing analysis: 2025-12-20*
*Update when test patterns change*
