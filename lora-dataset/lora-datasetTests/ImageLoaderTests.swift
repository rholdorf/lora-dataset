//
//  ImageLoaderTests.swift
//  lora-datasetTests
//

import Testing
import AppKit
@testable import lora_dataset

@Suite("ImageLoader CGImageSource decoding")
struct ImageLoaderTests {

    /// Creates a minimal valid 2x2 PNG file in the process temp directory.
    /// Returns the URL of the written file.
    private func makeTestPNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lora-dataset-test-image-\(UUID().uuidString).png")
        // Minimal 2x2 RGBA PNG: header + IHDR + IDAT + IEND
        // Generated via a 2x2 NSImage drawn into a CGBitmapContext
        let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        // Fill with an opaque red pixel
        let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        NSGraphicsContext.restoreGraphicsState()

        let pngData = bitmapRep.representation(using: .png, properties: [:])!
        try pngData.write(to: url)
        return url
    }

    // CACHE-04: Smoke test — loadImage returns a non-nil NSImage for a valid PNG
    @Test func testLoadsWithCGImageSource() throws {
        let url = try makeTestPNG()
        let result = loadImage(url: url, maxPixelSize: 128)
        #expect(result != nil)
    }

    // Returns nil for an invalid / nonexistent file
    @Test func testReturnsNilForInvalidFile() {
        let url = URL(fileURLWithPath: "/tmp/lora-dataset-nonexistent-\(UUID().uuidString).png")
        let result = loadImage(url: url, maxPixelSize: 128)
        #expect(result == nil)
    }
}
