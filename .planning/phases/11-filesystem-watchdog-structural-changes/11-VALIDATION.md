---
phase: 11
slug: filesystem-watchdog-structural-changes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`) |
| **Config file** | Embedded in `lora-datasetTests` target (no separate config file) |
| **Quick run command** | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests 2>&1 \| tail -20` |
| **Full suite command** | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset 2>&1 \| tail -30` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests 2>&1 | tail -20`
- **After every plan wave:** Run `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset 2>&1 | tail -30`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-01 | 01 | 0 | WATCH-01 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DirectoryWatcherTests` | ❌ W0 | ⬜ pending |
| 11-01-02 | 01 | 0 | WATCH-02 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DirectoryWatcherTests/testFileListUpdatesOnAdd` | ❌ W0 | ⬜ pending |
| 11-01-03 | 01 | 0 | WATCH-03 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DirectoryWatcherTests/testDebounceCoalescesEvents` | ❌ W0 | ⬜ pending |
| 11-01-04 | 01 | 0 | WATCH-04 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DirectoryWatcherTests/testWatcherReplacedOnNavigation` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `lora-datasetTests/DirectoryWatcherTests.swift` — stubs for WATCH-01, WATCH-02, WATCH-03, WATCH-04
- [ ] Add `remove(for:)` method to `ImageCacheActor` (needed by diff logic)

*Note: DirectoryWatcher tests operate on a real temp directory (created with `FileManager.default.createDirectory` in test setup, cleaned in teardown). No mock needed — the watcher is thin and tests against the real filesystem in /tmp. Tests use Swift Testing's async patterns with timeouts to wait for the debounce to fire.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| O_EVTONLY works with security-scoped bookmarks | WATCH-01 | Sandbox interaction not testable in unit tests | Open app, select folder via picker, add file in Finder, verify sidebar updates |
| Scroll position preserved on external changes | WATCH-02 | Requires visual inspection | Scroll to middle of list, add file in Finder, verify scroll didn't jump |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
