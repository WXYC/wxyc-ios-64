//
//  PosterArt.swift
//  WXYC
//
//  Poster helpers shared by the On Tour surfaces — the concert-detail hero
//  (`ConcertDetailView`) and the For You rail cards (`ForYouShelfView`): the
//  `PosterRGB → Color` bridge for the deterministic gradient fallback, and the
//  `fillClipped` wrapper that bounds oversized fill artwork to its frame.
//  Extracted so the two surfaces share one copy instead of divergent
//  reimplementations (#493 review).
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import SwiftUI

extension Color {
    /// Builds a SwiftUI color from the package's plain-data ``PosterRGB``.
    init(_ rgb: PosterRGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// Poster-artwork layout helpers shared by the On Tour concert surfaces.
enum PosterArt {
    /// Bounds oversized fill artwork to its frame. `scaledToFill` reports a size
    /// *larger* than the proposal for any aspect ratio that doesn't match the box
    /// — a landscape poster fitted to a fixed height reports a width wider than
    /// the frame. That oversized width escapes `.clipped()` (which clips drawing,
    /// not layout) and blows out the enclosing width, bleeding content past the
    /// edges. Drawing the fill over a `Color.clear` — which reports exactly the
    /// proposed size — pins the reported size back to the frame while the trailing
    /// `.clipped()` trims the overflow.
    static func fillClipped<Content: View>(_ content: Content) -> some View {
        Color.clear.overlay { content }.clipped()
    }
}
