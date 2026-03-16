import SwiftUI
import AppKit

/// NSViewRepresentable wrapping NSTextView with LoRA-safe settings.
///
/// Features:
/// - EDIT-01: Continuous spell checking (red underlines on misspelled words)
/// - EDIT-02: Grammar checking (green underlines on grammar issues)
/// - EDIT-03: Look Up in context menu (built-in to NSTextView, no code required)
/// - EDIT-04: Smart quotes and smart dashes disabled (protects LoRA training tokens)
/// - EDIT-05: Auto-language detection via NSSpellChecker (adapts to typed language)
/// - All silent substitutions disabled (auto-correction, text replacement, link/data detection)
/// - Per-image undo history (cleared on image switch, isolated from window undo manager)
struct CaptionEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView

        // Delegate: text change sync + dedicated undo manager
        tv.delegate = context.coordinator

        // Plain text — no rich text formatting
        tv.isRichText = false

        // Undo enabled (NSTextView registers edits with the coordinator's NSUndoManager)
        tv.allowsUndo = true

        // EDIT-01: Continuous spell checking (red underlines)
        tv.isContinuousSpellCheckingEnabled = true

        // EDIT-02: Grammar checking (green underlines)
        tv.isGrammarCheckingEnabled = true

        // EDIT-05: Auto-language detection (NSSpellChecker global setting)
        // Typically already true by default; set explicitly to be certain
        NSSpellChecker.shared.automaticallyIdentifiesLanguages = true

        // LoRA-safe: disable all silent substitutions that could corrupt training data
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false

        // Layout: vertically resizable, no horizontal scrolling
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]

        // Font: monospace is appropriate for LoRA training data captions
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        // Internal padding
        tv.textContainerInset = NSSize(width: 8, height: 8)

        // Background: transparent to blend with SwiftUI
        scrollView.drawsBackground = false
        tv.drawsBackground = false

        // Initial text
        tv.string = text

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let tv = nsView.documentView as! NSTextView

        // Re-apply substitution settings defensively in case SwiftUI update cycles reset them
        // Guard with firstSetupDone to only run this once after makeNSView
        if !context.coordinator.substitutionsVerified {
            context.coordinator.substitutionsVerified = true
            tv.isContinuousSpellCheckingEnabled = true
            tv.isGrammarCheckingEnabled = true
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticLinkDetectionEnabled = false
            tv.isAutomaticDataDetectionEnabled = false
        }

        // Only update text when the change originated outside the text view
        // (e.g., image switch, caption reload from disk)
        guard !context.coordinator.isUpdatingProgrammatically else { return }
        if tv.string != text {
            context.coordinator.isUpdatingProgrammatically = true
            // Clear undo history when text is reset from an external source
            // (image switch or reload — each image gets a fresh undo stack)
            context.coordinator.textViewUndoManager.removeAllActions()
            tv.string = text
            context.coordinator.isUpdatingProgrammatically = false
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptionEditorView
        /// Guards against feedback loop: updateNSView -> tv.string -> textDidChange -> updateNSView
        var isUpdatingProgrammatically = false
        /// Tracks whether re-application of substitution settings has been done after first update
        var substitutionsVerified = false
        /// Dedicated per-editor undo manager; isolated from the window's shared undo manager.
        /// Stored here so the same instance is returned on every undoManager(for:) call.
        let textViewUndoManager = UndoManager()

        init(_ parent: CaptionEditorView) { self.parent = parent }

        /// Sync text changes back to the SwiftUI binding
        func textDidChange(_ notification: Notification) {
            guard !isUpdatingProgrammatically,
                  let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
        }

        /// Provide a dedicated undo manager so NSTextView's history is isolated per-image.
        /// Returning the window's default undo manager would let Cmd+Z cross image boundaries.
        func undoManager(for view: NSTextView) -> UndoManager? {
            textViewUndoManager
        }
    }
}

// MARK: - Testing Support

extension CaptionEditorView {
    /// Creates an NSScrollView using the same makeNSView logic, for use in unit tests.
    /// This avoids needing to construct an NSViewRepresentable.Context in test code.
    func makeNSViewForTesting() -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let tv = scrollView.documentView as! NSTextView

        tv.isRichText = false
        tv.allowsUndo = true

        tv.isContinuousSpellCheckingEnabled = true
        tv.isGrammarCheckingEnabled = true

        NSSpellChecker.shared.automaticallyIdentifiesLanguages = true

        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false

        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]

        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        tv.textContainerInset = NSSize(width: 8, height: 8)

        scrollView.drawsBackground = false
        tv.drawsBackground = false

        tv.string = text

        return scrollView
    }
}
