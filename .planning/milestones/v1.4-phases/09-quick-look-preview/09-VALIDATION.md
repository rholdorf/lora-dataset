---
phase: 9
slug: quick-look-preview
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-16
---

# Phase 9 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Swift Testing (`import Testing`) — Xcode 16 built-in |
| **Config file** | None — Xcode scheme based |
| **Quick run command** | `xcodebuild test -project lora-dataset/lora-dataset.xcodeproj -scheme lora-dataset` |
| **Full suite command** | Same (single scheme) |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run app, press spacebar, verify floating panel appears — manual smoke test
- **After every plan wave:** Same manual test + verify panel follows selection + verify context menu still works
- **Before `/gsd:verify-work`:** All three requirements visually verified
- **Max feedback latency:** ~30 seconds (build + launch)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | QLPV-01 | manual-only | N/A | N/A | ⬜ pending |
| 09-01-02 | 01 | 1 | QLPV-02 | manual-only | N/A | N/A | ⬜ pending |
| 09-01-03 | 01 | 1 | QLPV-03 | manual-only | N/A | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

No new test files required. `QLPreviewPanel` requires a running macOS window server and the shared panel singleton — it cannot be exercised in a headless `xcodebuild test` context. All three requirements are UI/behavior requirements verifiable only by running the app.

**Optional supplemental unit tests** (not gating):
- `DatasetViewModel.toggleQuickLook()` guard logic (no crash when `selectedID == nil`)
- `numberOfPreviewItems` returns 0 when no selection, 1 when selection present

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Spacebar opens QL panel for selected image | QLPV-01 | `QLPreviewPanel` requires running window server; cannot be tested headless | 1. Select image in sidebar 2. Press spacebar 3. Verify floating panel shows image |
| Spacebar/Escape dismisses panel | QLPV-02 | Same — panel lifecycle requires live window | 1. Open QL panel 2. Press spacebar — verify dismiss 3. Reopen 4. Press Escape — verify dismiss |
| Panel appears as floating window, not sheet | QLPV-03 | Visual verification — must confirm window type | 1. Open QL panel 2. Verify it floats above app window 3. Verify it is not attached as a sheet |

---

## Validation Sign-Off

- [ ] All tasks have manual verification instructions
- [ ] Manual-only justification documented (QLPreviewPanel singleton requires window server)
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
