//
//  ImageLoader.swift
//  lora-dataset
//
//  Decodes images at display size using CGImageSource to avoid loading full
//  resolution pixel data into memory. This is the decode path used by
//  ImageCacheActor for both on-demand and prefetch loads.
//

import Foundation
import AppKit
import ImageIO

/// Loads an image from `url`, decoding it as a thumbnail at `maxPixelSize` on
/// the longest side.  Uses CGImageSource so the OS decodes only the requested
/// pixels and respects EXIF orientation.
///
/// - Parameters:
///   - url: File URL to the image.
///   - maxPixelSize: Maximum pixel dimension (width or height) of the decoded
///     result.  Pass the view's pixel dimension to avoid over-decoding.
/// - Returns: An `NSImage` backed by the decoded CGImage, or `nil` if the
///   file cannot be read or is corrupt.
func loadImage(url: URL, maxPixelSize: Int) -> NSImage? {
    let sourceOptions: [CFString: Any] = [
        kCGImageSourceShouldCache: false  // don't cache the compressed source data
    ]

    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
        return nil
    }

    let thumbnailOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,   // create even if no embedded thumb
        kCGImageSourceCreateThumbnailWithTransform: true,     // respect EXIF orientation
        kCGImageSourceShouldCacheImmediately: true,           // decode pixels now, not on first draw
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
        return nil
    }

    // Set the NSImage size in display points, not raw pixels.  The cgImage
    // dimensions are in physical pixels (up to maxPixelSize).  NSImage.size
    // must be in logical points so that callers such as ZoomablePannableImage
    // can compute a correct fit-scale without knowing the display scale factor.
    //
    // NSScreen.main is safe to access from any thread on macOS.  We fall back
    // to 2.0 (standard Retina) if the screen is unavailable at decode time.
    let scale = NSScreen.main?.backingScaleFactor ?? 2.0
    let pointWidth  = CGFloat(cgImage.width)  / scale
    let pointHeight = CGFloat(cgImage.height) / scale
    return NSImage(cgImage: cgImage, size: NSSize(width: pointWidth, height: pointHeight))
}
