//
//  SongRowPanel.swift
//  WXYC
//
//  The wallpaper-blurred card chrome shared by the flowsheet's plain song row
//  (`PlaycutRowView`) and the Liked tab row (`LikedSongRow`): a `BackgroundLayer`
//  behind a `SongRowContent`, sized to the 2.5-aspect row, with one tap target
//  over the whole card. Extracting it keeps the two surfaces' chrome in a single
//  place; per-surface extras (the flowsheet's scroll-shadow, the Liked row's
//  artwork prefetch) are applied by the caller, and the hairline border is opt-in
//  via `stroked` since only the Liked row draws one.
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper

/// The card chrome behind a `SongRowContent`. The caller supplies the row body
/// (via the `GeometryReader` proxy that sizes its artwork) and the tap action;
/// this view owns the background, the 2.5 aspect ratio, the rounded hit area,
/// and the optional hairline border.
struct SongRowPanel<Content: View>: View {
    var cornerRadius: CGFloat = 12
    /// Whether to draw the hairline border. The Liked row does; the flowsheet's
    /// plain row does not — the difference is preserved rather than unified.
    var stroked: Bool = false
    let onTap: () -> Void
    @ViewBuilder var content: (GeometryProxy) -> Content

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                BackgroundLayer(cornerRadius: cornerRadius)
                content(proxy)
            }
            .overlay {
                if stroked {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
            }
            .contentShape(.rect(cornerRadius: cornerRadius))
            .onTapGesture(perform: onTap)
        }
        .aspectRatio(2.5, contentMode: .fill)
        .frame(maxWidth: .infinity)
    }
}
