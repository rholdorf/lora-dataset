//
//  CaptionEditorViewTests.swift
//  lora-datasetTests
//

import Testing
import AppKit
@testable import lora_dataset

@Suite("CaptionEditorView NSTextView configuration", .serialized)
@MainActor
struct CaptionEditorViewTests {

    /// Helper: extract configured NSTextView from CaptionEditorView
    private func makeTextView() -> NSTextView {
        let editorView = CaptionEditorView(text: .constant("test caption"))
        let scrollView = editorView.makeNSViewForTesting()
        return scrollView.documentView as! NSTextView
    }

    // EDIT-01: Continuous spell checking enabled (red underlines on misspelled words)
    @Test func testSpellCheckEnabled() {
        let tv = makeTextView()
        #expect(tv.isContinuousSpellCheckingEnabled == true)
    }

    // EDIT-02: Grammar checking enabled (green underlines on grammar issues)
    @Test func testGrammarCheckEnabled() {
        let tv = makeTextView()
        #expect(tv.isGrammarCheckingEnabled == true)
    }

    // EDIT-04: Smart substitutions disabled (protect LoRA training data tokens)
    @Test func testSmartSubstitutionsDisabled() {
        let tv = makeTextView()
        #expect(tv.isAutomaticQuoteSubstitutionEnabled == false)
        #expect(tv.isAutomaticDashSubstitutionEnabled == false)
    }

    // EDIT-05: Auto-language detection active (spell check adapts to detected language)
    @Test func testAutoLanguageDetection() {
        #expect(NSSpellChecker.shared.automaticallyIdentifiesLanguages == true)
    }

    // LoRA-safe: All silent substitutions and auto-corrections are disabled
    @Test func testLoRASafeSettings() {
        let tv = makeTextView()
        #expect(tv.isAutomaticSpellingCorrectionEnabled == false)
        #expect(tv.isAutomaticTextReplacementEnabled == false)
        #expect(tv.isAutomaticLinkDetectionEnabled == false)
        #expect(tv.isAutomaticDataDetectionEnabled == false)
    }

    // Plain text mode (no rich text formatting)
    @Test func testIsPlainText() {
        let tv = makeTextView()
        #expect(tv.isRichText == false)
    }

    // Undo is enabled
    @Test func testAllowsUndo() {
        let tv = makeTextView()
        #expect(tv.allowsUndo == true)
    }
}
