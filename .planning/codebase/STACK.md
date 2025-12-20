# Technology Stack

**Analysis Date:** 2025-12-20

## Languages

**Primary:**
- Swift 5.0 - All application code (`lora-dataset/lora-dataset.xcodeproj/project.pbxproj`)

**Secondary:**
- None detected

## Runtime

**Environment:**
- Swift 5.0 runtime
- macOS 15.5+ deployment target - `lora-dataset/lora-dataset.xcodeproj/project.pbxproj`
- Xcode 16.4 toolchain

**Package Manager:**
- Swift Package Manager (SPM) - built into Xcode
- No external package dependencies

## Frameworks

**Core:**
- SwiftUI - UI framework (`lora_datasetApp.swift`, `ContentView.swift`, `ZoomablePannableImage.swift`)
- AppKit - Native macOS integration (`NSImage`, `NSOpenPanel`, `NSView`, `NSViewRepresentable`)
- Foundation - File operations, URL handling, data structures

**Testing:**
- Swift Testing - Modern unit testing framework (`lora_datasetTests.swift`)
- XCTest - UI and integration testing (`lora_datasetUITests.swift`, `lora_datasetUITestsLaunchTests.swift`)

**Build/Dev:**
- Xcode 16.4 - IDE and build system
- Swift compiler 5.0

## Key Dependencies

**Critical:**
- Zero external dependencies - Pure native macOS application

**Infrastructure:**
- FileManager - Directory scanning, file operations (`DatasetViewModel.swift`)
- UserDefaults - Persistent storage for security-scoped bookmarks (`DatasetViewModel.swift`)
- NSOpenPanel - Folder picker dialog (`DatasetViewModel.swift`)

## Configuration

**Environment:**
- UserDefaults for persistent state (security-scoped bookmarks)
- No environment variables required
- macOS App Sandbox with entitlements (`lora_dataset.entitlements`)

**Build:**
- Xcode project configuration: `lora-dataset.xcodeproj/project.pbxproj`
- App entitlements: `lora-dataset/lora-dataset/lora_dataset.entitlements`
- Bundle identifier: `holdorf.lora-dataset`

## Platform Requirements

**Development:**
- macOS with Xcode 16.4 or later
- No additional tooling required
- No Docker or external services

**Production:**
- macOS 15.5 or later
- Distributed as standalone macOS application
- Runs entirely offline (no network requirements)

**Supported File Formats:**
- Images: jpg, jpeg, png, webp, bmp, tiff
- Captions: txt, caption

---

*Stack analysis: 2025-12-20*
*Update after major dependency changes*
