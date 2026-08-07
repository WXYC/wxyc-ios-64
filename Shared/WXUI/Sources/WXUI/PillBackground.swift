//
//  PillBackground.swift
//  WXUI
//
//  The capsule-height background trick duplicated at the playlist's seam chip
//  (`SeamRowView`) and its plain text row (`TextRowView`): a `GeometryReader`
//  wrapped around the fill, sized to the content's own rendered height, so a
//  pill reads as a true capsule (corner radius = half its height) regardless of
//  the content's font-metric-dependent height rather than a hand-picked radius
//  that only matches one font size.
//
//  The fill is injected (`background`), for the same reason `WallpaperCard`
//  injects its background: both production call sites pass Wallpaper's
//  `BackgroundLayer(cornerRadius:)`, and `Wallpaper` depends on `WXUI` — so WXUI
//  importing Wallpaper back would be a package dependency cycle.
//
//  The resolved radius crosses the closure boundary as a `Double`, not the
//  more natural `CGFloat`: a generic function of the shape
//  `<T: View>(_: (CGFloat) -> T)` reliably crashes the Swift 6.2 frontend's
//  debug-info generation (`disable-round-trip-debug-types`) — reproduced in a
//  from-scratch SwiftPM package with no WXYC code involved, so it's a toolchain
//  limitation, not a bug in this file. Swap to `CGFloat` once the toolchain
//  fixes it; callers currently do `CGFloat(radius)` at the call site.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

public extension View {
    /// Backs this view with `background`, sized by a `GeometryReader` to the
    /// view's own rendered height and given a corner radius of half that
    /// height — so the background reads as a true capsule no matter what font
    /// or content sets the pill's height.
    ///
    /// - Parameter background: Builds the fill given the resolved corner
    ///   radius (half the rendered height), as a `Double` — see the file
    ///   header for why it isn't `CGFloat`. Every current caller passes
    ///   Wallpaper's `BackgroundLayer(cornerRadius: CGFloat(radius))`, but
    ///   this modifier doesn't depend on that type.
    func pillBackground<Background: View>(
        @ViewBuilder background: @escaping (Double) -> Background
    ) -> some View {
        self.background(
            GeometryReader { proxy in
                background(Double(PillBackgroundGeometry.cornerRadius(forHeight: proxy.size.height)))
            }
        )
    }
}

/// The pure geometry rule behind ``View/pillBackground(background:)``: a
/// capsule's corner radius is half its rendered height. Kept as its own type —
/// rather than inlined in the modifier's closure — so the halving rule is
/// directly reachable from tests via `@testable import WXUI`.
enum PillBackgroundGeometry {
    static func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        height / 2
    }
}
