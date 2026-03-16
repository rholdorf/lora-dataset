---
status: awaiting_human_verify
trigger: "Holding down arrow key during rapid image navigation causes the list selection to desync — selecting items already scrolled past. Image display is too tightly coupled to list navigation, causing feedback loops. Multiple sub-issues reported."
created: 2026-03-16T00:00:00Z
updated: 2026-03-16T00:15:00Z
---

## Current Focus

hypothesis: CONFIRMED (bug 8) — DetailView and CaptionEditingContainer observe vm.selectedID (@Published), which fires on every keypress. Even with image loading debounced, the detail pane still rebuilds on every arrow keypress because of selectedID being @Published and observed.
test: Introduced vm.detailID: UUID? — debounced mirror of selectedID. All detail pane views (filename label, caption editor, image display) now observe detailID. selectedID still changes instantly per keypress for List highlight. detailID updates 150ms after navigation settles, triggering a single detail pane refresh.
expecting: Hold arrow key → List scrolls freely at full key-repeat rate (~20 items/sec), detail pane stays frozen showing previous image/caption during rapid navigation. When key is released, detail pane updates once to show the final selection.
next_action: await human verification

## Symptoms

expected: List scrolls freely during rapid arrow-key navigation. Image panel always shows the most recently selected image. If the current selection isn't cached, it loads immediately. Prefetch of neighbors only triggers after user stops. Images display at view size, not original size.
actual: (1) List selection gets confused during rapid navigation — ends up selecting items already passed. (2) Image loading and list navigation appear to interfere with each other (too tightly coupled). (3) Images occasionally display at original size instead of display size, showing cropped. (4) Prefetch fires on every selection change even during rapid scrolling, wasting resources. (5) The user wants a LIFO/debounce pattern where rapid selection changes accumulate and the image panel focuses on showing only the most recent selection, discarding stale load requests. (6) Holding arrow key for 2-3s only advances ~6 images instead of ~20 like Finder. (7) Previously-displayed image occasionally flashes at original resolution (cropped). (8) Each arrow key advance causes a visible pause — caption text and filename display are updated synchronously on every single selection change, causing expensive SwiftUI re-renders that block the main thread.
errors: No crashes, just visual/behavioral issues.
reproduction: Hold down the arrow key in the image list to rapidly scroll through items. Observe list selection desyncing and images loading at wrong sizes.
timeline: After Phase 10 implementation of image cache + prefetch system. Issues (6) and (7) reported after round 1 fixes. Issue (8) reported after round 2 fixes.

## Eliminated

(none)

## Evidence

- timestamp: 2026-03-16T00:01:00Z
  checked: ContentView.swift onChange(of: selectedFileID) and onChange(of: vm.selectedID)
  found: Two-way sync between selectedFileID and vm.selectedID creates a feedback loop. When SwiftUI List changes selectedFileID, the onChange fires, sets vm.selectedID, which triggers vm.selectedID didSet (which fires @Published), which fires the onChange(of: vm.selectedID) handler, which sets selectedFileID again. During rapid arrow navigation this creates re-entrant async Tasks on the MainActor, and the async scheduling order can cause vm.selectedID to be set back to an earlier value after the arrow key has already advanced to a later one — causing selection desync.
  implication: Root cause of bug (1). Fixed in round 1.

- timestamp: 2026-03-16T00:01:00Z
  checked: ContentView.swift loadImageForSelection() — slow path
  found: The slow path fires a Task that does Task.detached for the image decode. There is no cancellation token for in-flight slow-path loads. If the user presses arrow 10 times rapidly, 10 Tasks are enqueued. Each one captures capturedID and checks `self.selectedFileID == capturedID` AFTER the decode. But the decode can complete in arbitrary order, and on cache hit the image is shown instantly (racing with in-flight slow-path loads for previously-selected items). Crucially, `loadImageForSelection` does NOT cancel any previous in-flight Task — there is no stored task handle to cancel.
  implication: Root cause of bugs (2) and (5). Fixed in round 1.

- timestamp: 2026-03-16T00:01:00Z
  checked: ContentView.swift loadImageForSelection() — spinnerTask
  found: The spinner suppression check is `self.loadedImage == nil` — but loadedImage holds the PREVIOUS image. So when rapidly navigating, loadedImage is always non-nil (previous frame), the spinner never shows for slow paths, and the previous image remains. There is also no cancellation of stale spinnerTasks from prior selections — they still fire 150ms later and update showSpinner.
  implication: Related to bug (2). Fixed in round 1.

- timestamp: 2026-03-16T00:01:00Z
  checked: ImageLoader.swift loadImage(url:maxPixelSize:) and ContentView.swift line 44
  found: loadImage() creates an NSImage with `size: NSSize(width: cgImage.width, height: cgImage.height)`. This sets the NSImage's size to the pixel dimensions of the thumbnail (up to 800px), NOT to display points. When the view renders at 400pt (800 physical pixels on 2x Retina), the ZoomablePannableImage.resetToFit() computes fitScale = bounds.width / img.size.width = 400/800 = 0.5. At scale 0.5, only 400px of the 800px wide image are shown, so the image appears cropped / at half size rather than fitted. For 1x displays or images smaller than 800px the arithmetic happens to work, which explains why this is intermittent.
  implication: Root cause of bug (3) and (7). Partially mitigated in round 1 via needsFit retry in layout() and draw(), but the core arithmetic (pixel size in NSImage) was never corrected. Fixed properly in round 2.

- timestamp: 2026-03-16T00:01:00Z
  checked: DatasetViewModel.swift triggerPrefetch(aroundID:) — called from loadImageForSelection() on every cache hit AND every cache miss completion
  found: triggerPrefetch is called on every single selection change (both cache hit path at line 190 and cache miss path at line 220). During rapid navigation, 10 selections/second each triggers a prefetch window recalculation that: (a) cancels tasks outside the window, (b) starts new tasks for the window. This is CPU-wasting churn. The intention per symptom (4) is to only prefetch after the user pauses.
  implication: Root cause of bug (4). Fixed in round 1.

- timestamp: 2026-03-16T00:04:00Z
  checked: ContentView.swift loadImageForSelection() — synchronous section before Task body (lines 192-195 in pre-fix version)
  found: Lines 192-195 unconditionally wrote imageScale = 1.0, imageOffset = .zero, showSpinner = false, loadError = false on EVERY call. SwiftUI does not deduplicate @State writes — any assignment triggers view invalidation even if the value is unchanged. This means every arrow keypress caused 4 SwiftUI view re-renders on the main thread before any async work started. Each re-render called DetailView.body and ZoomablePannableImage.updateNSView() which called resetToFit() and set needsDisplay=true — scheduling an NSView repaint. This blocked the Cocoa event loop from processing the next keypress at full repeat rate (~10 presses/sec × 4 renders = 40 full re-renders/sec just from selection changes, before any image decoding).
  implication: Root cause of bug (6): navigation appeared slow because the main thread was saturated with SwiftUI re-renders + NSView repaints per keypress. Fixed in round 2.

- timestamp: 2026-03-16T00:04:00Z
  checked: ImageLoader.swift line 44 — NSImage size set to cgImage pixel dimensions
  found: `NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))` — cgImage.width and cgImage.height are pixel counts (up to maxPixelSize=800). On a 2x Retina screen the view bounds are 400pt×400pt. resetToFit() computes fitScale = min(400/800, 400/533) = 0.5. The image is rendered at scale 0.5, appearing cropped. This is consistent (always wrong on 2x Retina), not intermittent. The "flash" effect was because the previous image (from round-1 fixes that improved but didn't fully resolve the size issue) appeared at one scale, and the new image appeared at a different wrong scale.
  implication: Root cause of bug (7): fixed in round 2 by dividing pixel dims by NSScreen.main?.backingScaleFactor.

- timestamp: 2026-03-16T00:10:00Z
  checked: DatasetViewModel.swift selectedID didSet + DetailView.body + CaptionEditingContainer.body
  found: vm.selectedID is @Published. Every keypress writes vm.selectedID, firing objectWillChange. DetailView is @ObservedObject var vm, so every objectWillChange fires DetailView.body. DetailView.body runs syncCaptionFilename() on onChange(of: vm.selectedID) which writes captionFilename @State — another re-render. CaptionEditingContainer also observes vm.selectedID and runs flushAndSync() on every keypress, which: (a) does vm.pairs.firstIndex linear scan; (b) writes pairs[idx].captionText (another @Published write, another objectWillChange, another full DetailView re-render); (c) writes localText @State; (d) writes savedText @State; (e) calls vm.setEditingDirty() which may fire objectWillChange. ALSO: vm.selectedID didSet does UserDefaults.standard.set() on every single keypress (disk write), and updateQuickLookIfVisible() on every keypress. The image loading IS debounced correctly, but the detail pane rebuilds from scratch on every single keypress regardless.
  implication: Root cause of bug (8). Fixed in round 3.

- timestamp: 2026-03-16T00:15:00Z
  checked: Round 3 fix applied — vm.detailID added as debounced mirror of selectedID
  found: BUILD SUCCEEDED, all 16 tests pass. Architecture: selectedFileID/vm.selectedID changes instantly per keypress for List highlight only. scheduleDetailDebounce() sets vm.detailID 150ms after last keypress. onChange(of: vm.detailID) triggers loadImageForSelection(), DetailView.syncCaptionFilename(), CaptionEditingContainer.flushAndSync(). UserDefaults write and QL update moved to detailID.didSet. External selection changes (folder nav, QL navigation, session restore) call commitDetailID() which sets detailID immediately without debounce.
  implication: During rapid navigation: List highlight moves freely. Detail pane (image, filename, caption, UserDefaults, QL) frozen. On pause: single detail pane refresh.

## Resolution

root_cause: Eight distinct bugs:
  (1) Two-way sync feedback loop — fixed in round 1.
  (2+5) No task cancellation / no LIFO — fixed in round 1.
  (3+7) NSImage created with pixel dimensions — partially mitigated in round 1; properly fixed in round 2 by computing display-point size in loadImage().
  (4) Prefetch not debounced — fixed in round 1.
  (6) loadImageForSelection() wrote 4 @State properties unconditionally on every keypress, causing 4 SwiftUI re-renders + NSView repaints per keypress, saturating the event loop and throttling arrow-key repeat rate — fixed in round 2.
  (8) DetailView and CaptionEditingContainer observe vm.selectedID (@Published) directly, causing full detail pane rebuild on every keypress. vm.selectedID didSet also does UserDefaults write and QL update per keypress — fixed in round 3 by adding vm.detailID (debounced mirror) and routing all detail pane observation through it.

fix: Round 3 fixes applied:
  DatasetViewModel.swift: Added @Published var detailID: UUID?. Moved UserDefaults write and updateQuickLookIfVisible() from selectedID.didSet to detailID.didSet. scanCurrentDirectory() sets detailID = selectedID immediately after initial load (no debounce needed for folder load). updateQuickLookIfVisible() now looks up pair via detailID.
  ContentView.swift: Added @State detailDebounceTask. onChange(of: selectedFileID) now calls scheduleDetailDebounce() instead of loadImageForSelection(). onChange(of: vm.selectedID) calls commitDetailID() (immediate, for external navigation). onChange(of: vm.pairs) calls commitDetailID(). Added onChange(of: vm.detailID) that calls loadImageForSelection(). loadImageForSelection() now guards on vm.detailID instead of selectedFileID. DetailView and CaptionEditingContainer now observe vm.detailID instead of vm.selectedID for all sync operations.

verification: BUILD SUCCEEDED, all 16 tests pass.
files_changed:
  - lora-dataset/lora-dataset/DatasetViewModel.swift
  - lora-dataset/lora-dataset/ContentView.swift
