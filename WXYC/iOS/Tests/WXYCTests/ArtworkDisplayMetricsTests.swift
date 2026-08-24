//
//  ArtworkDisplayMetricsTests.swift
//  WXYC
//
//  Pins the pure half-resolution artwork-cache formula that `ArtworkDisplayMetrics`
//  centralizes, and smoke-checks that the platform screen reads return sane
//  positive values on the running host. The type exists so the main-screen
//  coupling (`UIScreen` on iOS, `NSScreen` on macOS) lives behind one seam the
//  Mac target can reuse.
//
//  Created by Jake Bromberg on 08/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import Testing
@testable import WXYC

@Suite("ArtworkDisplayMetrics")
struct ArtworkDisplayMetricsTests {
    @Test("Cache target width is half the reference width at the given scale")
    func cacheTargetWidthIsHalfResolution() {
        // 390pt logical width at @3x → 1170px native, halved to 585px: artwork
        // renders at ~40% of screen width in rows, so half-resolution is ample.
        #expect(ArtworkDisplayMetrics.cacheTargetWidth(referenceWidth: 390, scale: 3) == 585)
    }

    @Test("Cache target width scales linearly with the reference width")
    func cacheTargetWidthScalesLinearly() {
        let single = ArtworkDisplayMetrics.cacheTargetWidth(referenceWidth: 100, scale: 2)
        let double = ArtworkDisplayMetrics.cacheTargetWidth(referenceWidth: 200, scale: 2)
        #expect(double == single * 2)
    }

    @Test("The platform screen reads return positive metrics on the host")
    @MainActor
    func platformReadsArePositive() {
        #expect(ArtworkDisplayMetrics.artworkReferenceWidth > 0)
        #expect(ArtworkDisplayMetrics.viewportHeight > 0)
        #expect(ArtworkDisplayMetrics.scale > 0)
    }
}
