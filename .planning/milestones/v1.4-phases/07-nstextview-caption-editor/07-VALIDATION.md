---
phase: 7
slug: nstextview-caption-editor
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-15
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Xcode built-in) |
| **Config file** | lora-dataset/lora-dataset.xcodeproj (scheme: lora-dataset) |
| **Quick run command** | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset 2>&1 \| tail -20` |
| **Full suite command** | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset 2>&1 | tail -20`
- **After every plan wave:** Run `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 0 | EDIT-01, EDIT-02, EDIT-04, EDIT-05 | unit | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests/CaptionEditorViewTests` | ❌ W0 | ⬜ pending |
| 07-01-02 | 01 | 1 | EDIT-01, EDIT-02, EDIT-03, EDIT-04 | integration | `xcodebuild build -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset` | ✅ | ⬜ pending |
| 07-01-03 | 01 | 1 | EDIT-03 | manual | N/A — requires right-click UI interaction | manual | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `lora-dataset/lora-datasetTests/CaptionEditorViewTests.swift` — stubs for EDIT-01, EDIT-02, EDIT-04, EDIT-05 (NSTextView property assertions)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| "Look Up" menu item in context menu | EDIT-03 | NSMenu population requires UI interaction; XCUITest would add disproportionate complexity | 1. Run app, open a dataset folder. 2. Type a word in the caption editor. 3. Right-click the word. 4. Verify "Look Up [word]" appears in the context menu. 5. Click it and verify the system dictionary popover appears. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
