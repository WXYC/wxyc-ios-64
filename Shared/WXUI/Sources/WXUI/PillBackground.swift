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
//  more natural `CGFloat`, because a generic function whose parameter is a
//  generic-dependent function type mentioning `CGFloat` emits debug info the
//  compiler cannot read back:
//
//      Failed to reconstruct type for $s12CoreGraphics7CGFloatVxIgyr_D
//      Abort: function getMangledName at IRGenDebugInfo.cpp:1105
//
//  Reduced to two lines with no SwiftUI and no WXYC code — `import CoreGraphics`
//  plus `func f<T>(_ body: (CGFloat) -> T) {}` under `-g`. `Double`, `Float`,
//  `Int`, `String`, and even `CGSize` all round-trip fine in the same position;
//  a non-generic `(CGFloat) -> Int` is fine. So this is a toolchain limitation
//  specific to `CGFloat` in a lowered generic function type, not a bug here.
//
//  **Do not "swap to CGFloat once the toolchain fixes it" — it is not fixed.**
//  An earlier version of this comment said that, and it is misleading. The
//  round-trip check that aborts is compiled out of assertions-disabled builds,
//  which is every Apple-shipped toolchain, so newer Xcodes only *appear* to
//  cope — they emit the same un-reconstructible mangled name into the DWARF:
//
//      swift.org swift-6.2-RELEASE (+assertions)  aborts under plain -g
//      Xcode 26.6  / Apple Swift 6.3.3            compiles, bad debug info
//      Xcode 27.0b / Apple Swift 6.4              compiles, bad debug info
//
//  All three abort when the check is re-enabled with
//  `-Xfrontend -enable-round-trip-debug-types`. Retire this workaround only
//  after that flag passes on the toolchain in use, not merely because a build
//  stopped crashing. A minimal reproducer and a filed-ready bug report live
//  outside the repo; regenerate with the two lines above if needed.
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
