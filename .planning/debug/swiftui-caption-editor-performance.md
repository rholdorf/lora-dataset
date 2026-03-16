---
status: awaiting_human_verify
trigger: "swiftui-caption-editor-performance"
created: 2026-03-16T00:00:00Z
updated: 2026-03-16T00:10:00Z
---

## Current Focus

hypothesis: CONFIRMED - see Resolution
test: complete
expecting: n/a
next_action: human verification

## Symptoms

expected: Smooth, responsive caption editing. Only the caption text field should update when typing. No excessive console logs.
actual: Interface is slow and resource-heavy. Every character typed in the caption panel triggers a console log `containerToPush is nil, will not push anything to candidate receiver for request token: 7090AE3E`. All UI components appear to re-render with each keystroke, not just the text editor.
errors: Console spam: `containerToPush is nil, will not push anything to candidate receiver for request token: 7090AE3E` on every keystroke
reproduction: Open the app, load a dataset directory, select an image, and start typing in the caption editor. Observe console logs and sluggish UI.
started: Appears to be an ongoing issue with the current implementation.

## Eliminated

(none - hypothesis confirmed on first investigation)

## Evidence

- timestamp: 2026-03-16T00:05:00Z
  checked: DatasetViewModel.swift - class declaration and @Published properties
  found: `class DatasetViewModel: ObservableObject` with `@Published var pairs: [ImageCaptionPair]`. Any mutation to pairs (including element mutation via subscript) fires objectWillChange to all subscribers.
  implication: Every write to pairs[idx].captionText triggers a full re-render of every view subscribed to vm.

- timestamp: 2026-03-16T00:05:01Z
  checked: ContentView.swift DetailView - the Binding created for CaptionEditorView
  found: `Binding(get: { vm.pairs[idx].captionText }, set: { vm.pairs[idx].captionText = $0 })` — the set closure directly writes into the @Published array on every keystroke.
  implication: Every character typed flows: textDidChange -> parent.text = tv.string -> this binding setter -> vm.pairs[idx].captionText = $0 -> @Published fires -> DetailView.body re-evaluates -> ZoomablePannableImage updateNSView invoked -> `nsView.needsDisplay = true` forces full image redraw.

- timestamp: 2026-03-16T00:05:02Z
  checked: ZoomablePannableImage.swift updateNSView
  found: Line 63: `nsView.needsDisplay = true` is called unconditionally on every updateNSView call, even when only the caption text changed and the image is unchanged.
  implication: The NSView redraws the image (calls draw(_:)) on every single keystroke, which is expensive.

- timestamp: 2026-03-16T00:05:03Z
  checked: DetailView uses @ObservedObject var vm: DatasetViewModel
  found: DetailView subscribes to the entire DatasetViewModel via @ObservedObject. Any @Published property change on vm re-evaluates DetailView.body entirely.
  implication: The DetailView has no way to selectively update — it re-renders everything (toolbar buttons, image panel, caption editor) on every keystroke because pairs is @Published and mutated on every keystroke.

- timestamp: 2026-03-16T00:05:04Z
  checked: `containerToPush is nil` log message origin
  found: This is an NSSpellChecker / input candidate system log. It fires when the spell checker tries to push a correction candidate but cannot find a valid input context (containerToPush is nil). Continuous spell checking (`isContinuousSpellCheckingEnabled = true`) triggers the spell checker pipeline on every text change, and the NSTextView's responder chain / input context is being queried. The re-render cycle (view being recreated or updateNSView disturbing the responder chain) causes this failure repeatedly.
  implication: The log is a symptom of the render storm — spell checker fires on every change AND the re-render disrupts the responder/input context, causing the nil container warning. Fixing the render storm should eliminate or greatly reduce this log.

- timestamp: 2026-03-16T00:05:05Z
  checked: CaptionEditorView.updateNSView guard logic
  found: `guard !context.coordinator.isUpdatingProgrammatically else { return }` and `if tv.string != text { ... tv.string = text }` correctly avoids feedback loops within the NSTextView. However, this guard only prevents the NSTextView from being programmatically updated — it does NOT prevent the parent DetailView and its siblings (ZoomablePannableImage) from re-rendering.
  implication: The guard is correct for the text editor, but doesn't solve the broader re-render problem. The root fix must prevent vm.pairs from broadcasting objectWillChange on every keystroke.

- timestamp: 2026-03-16T00:10:00Z
  checked: Build result after applying all three fixes
  found: BUILD SUCCEEDED, no warnings, no errors.
  implication: All changes are syntactically and semantically correct.

## Resolution

root_cause: |
  Every keystroke mutated vm.pairs[idx].captionText via an inline Binding in DetailView
  (get: { vm.pairs[idx].captionText }, set: { vm.pairs[idx].captionText = $0 }).
  pairs is @Published on DatasetViewModel (ObservableObject), so every mutation fires
  objectWillChange to all subscribers. DetailView (via @ObservedObject) re-evaluated its
  entire body including ZoomablePannableImage, whose updateNSView unconditionally called
  nsView.needsDisplay = true — triggering a full NSView image repaint on every keystroke.
  The NSSpellChecker containerToPush is nil log is a symptom: the continuous spell-check
  pipeline fires on every text change event, and the repeated re-render cycle disturbs the
  NSTextView responder/input context, causing the nil-container warning each time.

fix: |
  Three targeted changes:

  1. ContentView.swift — DetailView: Added @State private var localCaptionText: String
     to hold the live editing buffer. CaptionEditorView now binds to $localCaptionText
     (a stable @State binding) instead of the inline vm.pairs binding. onChange(of: localCaptionText)
     calls vm.updateCaption(_:for:) to keep vm in sync. onChange(of: vm.selectedID) and
     onChange(of: vm.captionReloadToken) sync localCaptionText from vm when selection changes
     or a caption is reloaded from disk.

  2. DatasetViewModel.swift: Added @Published var captionReloadToken: Int = 0 (incremented
     by reloadCaptionForSelected() to signal DetailView to re-sync). Added updateCaption(_:for:)
     method with a guard that short-circuits if the text is already up-to-date, avoiding
     redundant objectWillChange broadcasts when onChange fires with an unchanged value.

  3. ZoomablePannableImage.swift — updateNSView: Changed nsView.needsDisplay = true from
     unconditional to conditional on a needsRedraw flag that is only set when the image,
     scale, or offset actually changed. This eliminates the image repaint on re-renders
     triggered by caption text changes.

verification: Build succeeded with no errors or warnings. Human verification pending.
files_changed:
  - lora-dataset/lora-dataset/lora-dataset/ContentView.swift
  - lora-dataset/lora-dataset/lora-dataset/DatasetViewModel.swift
  - lora-dataset/lora-dataset/lora-dataset/ZoomablePannableImage.swift
