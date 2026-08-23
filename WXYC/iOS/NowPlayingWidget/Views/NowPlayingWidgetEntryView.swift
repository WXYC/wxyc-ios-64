//
//  NowPlayingWidgetEntryView.swift
//  WXYC
//
//  Shared widget entry view logic.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import WidgetKit

protocol NowPlayingWidgetEntryView: View {
    associatedtype Artwork: View
    
    var entry: NowPlayingTimelineEntry { get }
    var artwork: Artwork { get }
}

extension NowPlayingWidgetEntryView {
    @ViewBuilder
    var artwork: some View {
        if let artwork = entry.artwork {
            artwork
                .resizable()
                .frame(maxWidth: 800, maxHeight: 800)
                .aspectRatio(contentMode: .fit)
                .cornerRadius(5)
        } else {
            Image.logo
        }
    }
    
    @ViewBuilder
    var background: some View {
        Image.background
        
        Color.darken
            .ignoresSafeArea()
    }

    /// How long ago the displayed playcut aired, e.g. "12 min ago".
    ///
    /// The relative token re-renders itself as the clock advances without a
    /// new timeline entry, so this stays truthful between reloads at no cost
    /// to the refresh budget.
    ///
    /// The literal " ago" is not redundant: `Text`'s `.relative` style renders
    /// the magnitude alone ("12 min") with no indication of direction, which
    /// beside a track title reads just as easily as the song's length. Wrapping
    /// it in an interpolation keeps the token auto-updating while pinning the
    /// direction.
    ///
    /// Renders nothing for the placeholder and empty states, which have no
    /// broadcast time.
    @ViewBuilder
    var freshnessLabel: some View {
        if let playedAt = entry.playedAt {
            HStack(spacing: 4) {
                Text("\(playedAt, style: .relative) ago")
                if entry.isStale {
                    Text("· may be out of date")
                }
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(entry.isStale ? 0.5 : 0.7))
            .lineLimit(1)
        }
    }
}
