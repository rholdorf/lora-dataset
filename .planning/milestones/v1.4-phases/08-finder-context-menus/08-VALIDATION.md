---
phase: 8
slug: finder-context-menus
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
---

# Phase 8 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (via `import Testing`) |
| **Config file** | lora-dataset.xcodeproj scheme — no separate config file |
| **Quick run command** | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests` |
| **Full suite command** | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset`
- **After every plan wave:** Run `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | CTXM-01 | manual-only | N/A — SwiftUI context menu UI interaction | N/A | ⬜ pending |
| 08-01-02 | 01 | 1 | CTXM-02 | manual-only | N/A — SwiftUI context menu UI interaction | N/A | ⬜ pending |
| 08-01-03 | 01 | 1 | CTXM-03 | manual-only | N/A — requires OS interaction with Finder | N/A | ⬜ pending |
| 08-01-04 | 01 | 1 | CTXM-04 | unit (partial) | `xcodebuild test ... -only-testing:lora-datasetTests/OpenWithTests` | ❌ W0 | ⬜ pending |
| 08-01-05 | 01 | 1 | CTXM-05 | manual-only | N/A — requires visual panel verification | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `lora-datasetTests/OpenWithTests.swift` — unit tests for app list building logic (CTXM-04)

*Most phase behaviors are context menu UI and OS integration — only Open With app list logic is unit-testable.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| File row right-click shows context menu | CTXM-01 | SwiftUI context menu requires user interaction | Right-click any file row in sidebar; verify menu appears with Reveal in Finder, Open With, Quick Look |
| Folder row right-click shows context menu | CTXM-02 | SwiftUI context menu requires user interaction | Right-click any folder row; verify menu appears with Open in Finder, Open in Terminal |
| Reveal in Finder / Open in Finder works | CTXM-03 | Requires OS-level Finder interaction | Click "Reveal in Finder" on file; verify Finder opens with file selected. Click "Open in Finder" on folder; verify folder opens |
| Quick Look triggers panel | CTXM-05 | Requires visual panel verification | Click "Quick Look" on file row; verify QLPreviewPanel appears showing the image |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
