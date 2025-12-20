# Codebase Structure

**Analysis Date:** 2025-12-20

## Directory Layout

```
lora-dataset/
├── .git/                           # Version control
├── .planning/                      # Project planning and documentation
│   └── codebase/                   # Codebase mapping documents
├── CLAUDE.md                        # Project instructions for Claude Code
├── README.md                        # Project documentation
├── LICENSE                          # License file
└── lora-dataset/                    # Xcode project root
    ├── lora-dataset.xcodeproj/      # Xcode project configuration
    │   ├── project.pbxproj          # Build settings, targets, schemes
    │   ├── project.xcworkspace/     # Workspace data
    │   └── xcuserdata/              # User-specific settings
    │
    ├── lora-dataset/                # Main source code
    │   ├── Assets.xcassets/         # App assets
    │   │   ├── AccentColor.colorset/
    │   │   └── AppIcon.appiconset/
    │   ├── lora_datasetApp.swift              # App entry point (@main)
    │   ├── ContentView.swift                  # Main UI view
    │   ├── DatasetViewModel.swift             # ViewModel (state + logic)
    │   ├── ImageCaptionPair.swift             # Data model
    │   ├── ZoomablePannableImage.swift        # Custom image component
    │   └── lora_dataset.entitlements          # Sandbox permissions
    │
    ├── lora-datasetTests/           # Unit tests
    │   └── lora_datasetTests.swift
    │
    └── lora-datasetUITests/         # UI tests
        ├── lora_datasetUITests.swift
        └── lora_datasetUITestsLaunchTests.swift
```

## Directory Purposes

**lora-dataset/lora-dataset/** (Main source)
- Purpose: All application source code
- Contains: 5 Swift files + 1 entitlements file + assets
- Key files:
  - `lora_datasetApp.swift` - App lifecycle (@main entry)
  - `ContentView.swift` - Main UI (125 lines)
  - `DatasetViewModel.swift` - State management (197 lines)
  - `ImageCaptionPair.swift` - Data model (26 lines)
  - `ZoomablePannableImage.swift` - Custom view (262 lines)
  - `lora_dataset.entitlements` - macOS sandbox config
- Subdirectories: Assets.xcassets/ (icons and colors only)
- Organization: Flat structure (no subdirectories for code)

**lora-dataset/lora-datasetTests/**
- Purpose: Unit tests using Swift Testing framework
- Contains: `lora_datasetTests.swift` (placeholder test)
- Key files: Single test file with @Test annotations
- Subdirectories: None

**lora-dataset/lora-datasetUITests/**
- Purpose: UI automation tests using XCTest
- Contains: UI test files (launch tests, interaction tests)
- Key files:
  - `lora_datasetUITests.swift` - Main UI test suite
  - `lora_datasetUITestsLaunchTests.swift` - Launch screen tests
- Subdirectories: None

**lora-dataset.xcodeproj/**
- Purpose: Xcode project configuration
- Contains: Build settings, target definitions, schemes
- Key files: `project.pbxproj` - All build configuration
- Subdirectories: project.xcworkspace/, xcuserdata/

## Key File Locations

**Entry Points:**
- `lora-dataset/lora-dataset/lora_datasetApp.swift` - Application entry with @main

**Main UI:**
- `lora-dataset/lora-dataset/ContentView.swift` - NavigationSplitView with sidebar + detail pane

**State Management:**
- `lora-dataset/lora-dataset/DatasetViewModel.swift` - @MainActor ViewModel with business logic

**Data Models:**
- `lora-dataset/lora-dataset/ImageCaptionPair.swift` - Identifiable struct for image-caption pairs

**Custom Views:**
- `lora-dataset/lora-dataset/ZoomablePannableImage.swift` - NSViewRepresentable + NSView + Coordinator

**Configuration:**
- `lora-dataset/lora-dataset/lora_dataset.entitlements` - App Sandbox entitlements
- `lora-dataset.xcodeproj/project.pbxproj` - Build configuration

**Tests:**
- `lora-datasetTests/lora_datasetTests.swift` - Unit tests (Swift Testing)
- `lora-datasetUITests/lora_datasetUITests.swift` - UI tests (XCTest)

**Documentation:**
- `CLAUDE.md` - Instructions for Claude Code
- `README.md` - Project README

## Naming Conventions

**Files:**
- PascalCase for Swift source: `ContentView.swift`, `DatasetViewModel.swift`, `ImageCaptionPair.swift`
- snake_case for app entry and tests: `lora_datasetApp.swift`, `lora_datasetTests.swift`
- Extensions included: `.swift` for source, `.entitlements` for sandbox config

**Directories:**
- PascalCase with descriptive names: `Assets.xcassets`
- Test suffixes: `lora-datasetTests`, `lora-datasetUITests`

**Special Patterns:**
- App entry: `{ProjectName}App.swift` with @main attribute
- Test files: `{ProjectName}Tests.swift` or `{Feature}Tests.swift`
- Assets: `.xcassets` bundle format
- Entitlements: `{ProjectName}.entitlements`

## Where to Add New Code

**New Feature:**
- Primary code: `lora-dataset/lora-dataset/` (flat structure, no subdirs needed yet)
- ViewModel logic: Add to `DatasetViewModel.swift` or create new ViewModel
- Views: Add new file in `lora-dataset/lora-dataset/` with PascalCase naming
- Tests: Add to `lora-datasetTests/` or create new test file

**New UI Component:**
- Implementation: New `.swift` file in `lora-dataset/lora-dataset/`
- Pattern: Follow SwiftUI View protocol or NSViewRepresentable if AppKit needed
- Tests: UI tests in `lora-datasetUITests/`

**New Data Model:**
- Implementation: New struct/class in `lora-dataset/lora-dataset/`
- Pattern: Conform to Identifiable if used in List/ForEach
- Location: Alongside `ImageCaptionPair.swift`

**Utilities:**
- No separate utilities directory yet
- Add helper functions to existing files or create new utility file in main source directory
- Shared helpers: Consider creating `Extensions.swift` or `Utilities.swift`

## Special Directories

**Assets.xcassets/**
- Purpose: Compiled asset catalog for images, colors, icons
- Source: Managed by Xcode, compiled into app bundle
- Committed: Yes (source of truth for visual assets)
- Contains: AccentColor, AppIcon

**.planning/**
- Purpose: Project planning documentation (not part of app build)
- Source: Created by GSD workflow
- Committed: Yes (project documentation)
- Contains: Codebase mapping documents

**xcuserdata/**
- Purpose: User-specific Xcode settings (schemes, breakpoints)
- Source: Generated by Xcode per-user
- Committed: No (gitignored)

## Module Organization

**Single Target Application:**
- No internal frameworks or modules defined
- All code compiles into single `lora-dataset.app` executable
- Framework dependencies: SwiftUI, AppKit, Foundation (Apple system frameworks only)
- No Swift Package dependencies

**Import Pattern:**
```swift
import Foundation  // For FileManager, URL, String
import SwiftUI     // For UI components
import AppKit      // For NSImage, NSOpenPanel, NSView
import Testing     // For unit tests
import XCTest      // For UI tests
```

## Data Flow Architecture

```
User Interaction (ContentView)
        ↓
@StateObject ViewModel (DatasetViewModel)
        ↓
File System Operations (FileManager + Security-Scoped Access)
        ↓
@Published State Updates
        ↓
SwiftUI Auto-Refresh (Views)
```

**Sidebar/Detail Pattern:**
- Sidebar: List of ImageCaptionPair items
- Detail: HSplitView with ZoomablePannableImage + TextEditor
- Selection: Managed by `vm.selectedID` binding

**File Count Summary:**
- Source files: 5 Swift files
- Test files: 3 Swift files
- Configuration: 1 entitlements, 1 xcodeproj
- Documentation: 2 markdown files
- Total lines of code: ~810 lines across all Swift files

---

*Structure analysis: 2025-12-20*
*Update when directory structure changes*
