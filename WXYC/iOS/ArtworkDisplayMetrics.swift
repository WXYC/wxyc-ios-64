//
//  ArtworkDisplayMetrics.swift
//  WXYC
//
//  One seam over the main screen's metrics, so the artwork-cache sizing and the
//  scroll-shadow layout math don't reach for `UIScreen` at their call sites. The
//  iOS path reads `UIScreen.main`; the macOS path reads `NSScreen.main` (a Mac
//  window is far smaller than the desktop, so artwork sizes off a fixed
//  reference width rather than the screen). The Mac target reuses this file.
//
//  Created by Jake Bromberg on 08/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Main-screen metrics for artwork sizing and scroll-relative layout, resolved
/// once behind a single platform branch.
enum ArtworkDisplayMetrics {
    /// On macOS, artwork sizes off this fixed reference width rather than the
    /// desktop width — a Mac window shows artwork at roughly this size, and the
    /// desktop's full width would oversize the cache by an order of magnitude.
    static let macArtworkReferenceWidth: CGFloat = 600

    /// Fallback viewport height for the scroll-shadow math when no `NSScreen` is
    /// available (headless macOS); the iOS path always has `UIScreen.main`.
    static let macFallbackViewportHeight: CGFloat = 900

    /// Reference width (points) for sizing now-playing and cached artwork.
    ///
    /// iOS: the main screen's width. macOS: ``macArtworkReferenceWidth``.
    @MainActor
    static var artworkReferenceWidth: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.bounds.size.width
        #elseif canImport(AppKit)
        macArtworkReferenceWidth
        #endif
    }

    /// The backing scale factor used to size native-resolution artwork.
    ///
    /// iOS: `UIScreen.main.scale`. macOS: the main screen's backing scale factor
    /// (falling back to `2` when no screen is attached).
    @MainActor
    static var scale: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.scale
        #elseif canImport(AppKit)
        NSScreen.main?.backingScaleFactor ?? 2
        #endif
    }

    /// Viewport height (points) for scroll-relative layout, such as the playlist
    /// row's shadow-offset interpolation.
    ///
    /// iOS: the main screen's height. macOS: the main screen's height (falling
    /// back to ``macFallbackViewportHeight`` when no screen is attached).
    @MainActor
    static var viewportHeight: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.bounds.height
        #elseif canImport(AppKit)
        NSScreen.main?.frame.height ?? macFallbackViewportHeight
        #endif
    }

    /// The half-resolution artwork-cache target width in pixels.
    ///
    /// Artwork renders at roughly 40% of screen width in playlist rows, so
    /// caching at half the native resolution is more than sufficient and cuts
    /// per-image memory substantially (~5.5MB → ~1.4MB on a 3× phone).
    nonisolated static func cacheTargetWidth(referenceWidth: CGFloat, scale: CGFloat) -> CGFloat {
        referenceWidth * scale / 2
    }
}
