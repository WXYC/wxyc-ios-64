//
//  WallpaperCard.swift
//  WXUI
//
//  The wallpaper-tinted card chrome duplicated across three list/rail surfaces:
//  the flowsheet's plain song row and the Liked tab row (via the app target's
//  `SongRowPanel`, which this generalizes and now delegates to), the On Tour
//  list row (`ConcertRow`), and the On Tour "Heard on WXYC" rail card
//  (`ForYouShelfView`). Every site paired a theme-aware material fill with the
//  same 0.12-opacity hairline stroke and a matching rounded `contentShape` —
//  this is that pairing, with the fill itself supplied by the caller instead of
//  hardcoded.
//
//  The fill is injected (`background`) rather than reaching for Wallpaper's
//  `BackgroundLayer` directly because the `Wallpaper` package depends on `WXUI`
//  (for its picker and debug UI) — WXUI importing Wallpaper back would be a
//  package dependency cycle, not just a style choice. Every current call site
//  happens to pass `BackgroundLayer`, but this type stays unaware that it
//  exists.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// The rounded, wallpaper-tinted card chrome shared by the app's song/show list
/// rows and cards: a caller-supplied `background` behind `content`, an optional
/// hairline stroke, and a matching rounded `contentShape` so the whole card
/// reads as one hit target.
///
/// `WallpaperCard` owns none of a row's *layout* — sizing, tap handling, and
/// `GeometryReader`-based content sizing are the caller's concern. A card whose
/// content can visually overflow the rounded corners (an edge-to-edge poster
/// image, say) should add its own `.clipShape(.rect(cornerRadius:))` after this
/// view; `WallpaperCard`'s own `contentShape` only affects hit-testing, not
/// clipping — matching what the rows it generalizes already did.
public struct WallpaperCard<Background: View, Content: View>: View {
    /// The hairline stroke's opacity, over `.white`. Canon: 0.12.
    public static var borderOpacity: Double { 0.12 }
    /// The hairline stroke's line width. Canon: 1pt.
    public static var borderWidth: CGFloat { 1 }

    let cornerRadius: CGFloat
    let stroked: Bool
    @ViewBuilder let background: () -> Background
    @ViewBuilder let content: () -> Content

    /// - Parameters:
    ///   - cornerRadius: The corner radius shared by the stroke and the
    ///     `contentShape` (and, in practice, by whatever the caller passes as
    ///     `background`). Default 12pt — `SongRowPanel`'s prior default.
    ///   - stroked: Whether to draw the canon hairline border. Default
    ///     `false` — most adopting rows omit it; pass `true` for a card that
    ///     wants the Liked row / On Tour card's outline.
    ///   - background: The card's fill, drawn behind `content`. Every current
    ///     caller passes Wallpaper's `BackgroundLayer(cornerRadius:)`, but this
    ///     type doesn't depend on it — see the file header.
    ///   - content: The card's body.
    public init(
        cornerRadius: CGFloat = 12,
        stroked: Bool = false,
        @ViewBuilder background: @escaping () -> Background,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.stroked = stroked
        self.background = background
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            background()
            content()
        }
        .overlay {
            if Self.showsStroke(stroked: stroked) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(.white.opacity(Self.borderOpacity), lineWidth: Self.borderWidth)
            }
        }
        .contentShape(.rect(cornerRadius: cornerRadius))
    }

    /// Whether the hairline stroke renders for a given `stroked` flag. Exposed
    /// as a pure function (rather than inlined in `body`) so the branch is
    /// directly testable.
    static func showsStroke(stroked: Bool) -> Bool {
        stroked
    }
}
