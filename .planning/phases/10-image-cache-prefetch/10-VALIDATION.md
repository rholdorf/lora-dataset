---
phase: 10
slug: image-cache-prefetch
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (import Testing) — already in use |
| **Config file** | None — Xcode scheme-based |
| **Quick run command** | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests` |
| **Full suite command** | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset -only-testing:lora-datasetTests`
- **After every plan wave:** Run `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | CACHE-01 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageCacheActorTests/testCacheHitReturnsCachedImage` | ❌ W0 | ⬜ pending |
| 10-01-02 | 01 | 1 | CACHE-02 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageCacheActorTests/testCostAccounting` | ❌ W0 | ⬜ pending |
| 10-02-02 | 02 | 2 | CACHE-03 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DatasetViewModelCacheTests/testPrefetchEnqueuedForNeighbors` | ❌ W0 | ⬜ pending |
| 10-01-04 | 01 | 1 | CACHE-04 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageLoaderTests/testLoadsWithCGImageSource` | ❌ W0 | ⬜ pending |
| 10-01-05 | 01 | 1 | CACHE-05 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/ImageCacheActorTests/testMemoryPressureEviction` | ❌ W0 | ⬜ pending |
| 10-02-02 | 02 | 2 | CACHE-06 | unit | `xcodebuild test ... -only-testing:lora-datasetTests/DatasetViewModelCacheTests/testStalePrefetchCancelled` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `lora-datasetTests/ImageCacheActorTests.swift` — stubs for CACHE-01, CACHE-02, CACHE-03, CACHE-05, CACHE-06
- [ ] `lora-datasetTests/ImageLoaderTests.swift` — stubs for CACHE-04 (smoke test that loadImage returns non-nil NSImage for a known test image)

*Existing infrastructure covers framework — Swift Testing already in use in lora_datasetTests.swift and CaptionEditorViewTests.swift*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Rapid arrow-key scrubbing shows cached images, skips uncached | CACHE-06 | Requires real UI interaction timing | Open large dataset, hold down-arrow for 3+ seconds, verify no wrong images flash |
| Spinner appears after 150ms delay on cache miss | CACHE-01 | Timing-dependent UI behavior | Navigate to uncached image, observe spinner delay vs. instant load |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
