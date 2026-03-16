import SwiftUI
import AppKit

/// NSTextView subclass that applies LoRA-safe and grammar settings after
/// the view is added to a window — where NSTextView's user-defaults-backed
/// properties actually take effect.
private class CaptionTextView: NSTextView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }

        // EDIT-01: Continuous spell checking (red underlines)
        isContinuousSpellCheckingEnabled = true

        // EDIT-02: Grammar checking (green underlines)
        isGrammarCheckingEnabled = true

        // EDIT-05: Auto-language detection
        NSSpellChecker.shared.automaticallyIdentifiesLanguages = true

        // LoRA-safe: disable all silent substitutions
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
    }
}

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
        // Build the text system manually so we can use our CaptionTextView subclass
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let tv = CaptionTextView(frame: .zero, textContainer: textContainer)

        // Delegate: text change sync + dedicated undo manager
        tv.delegate = context.coordinator

        // Plain text — no rich text formatting
        tv.isRichText = false

        // Undo enabled
        tv.allowsUndo = true

        // Layout: vertically resizable, no horizontal scrolling
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        // Font: monospace is appropriate for LoRA training data captions
        tv.font = .monospacedSystemFont(ofSize: 13, weight: .regular)

        // Internal padding
        tv.textContainerInset = NSSize(width: 8, height: 8)

        // Background: transparent to blend with SwiftUI
        tv.drawsBackground = false

        // Initial text
        tv.string = text

        // Wrap in scroll view
        let scrollView = NSScrollView()
        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }

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
    /// Creates an NSScrollView with a configured CaptionTextView, for use in unit tests.
    /// This avoids needing to construct an NSViewRepresentable.Context in test code.
    func makeNSViewForTesting() -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let tv = CaptionTextView(frame: .zero, textContainer: textContainer)
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
        tv.drawsBackground = false
        tv.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = tv
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        return scrollView
    }
}
