//
//  NowPlayingWidgetEntryView.swift
//  WXYC
//
//  Shared widget entry view logic.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Artwork
import Playlist
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
}

/// The program's logo, or its text tile when there is none, square at `size`. Used for the small widget's
/// corner badge and tile and the medium widget's 18-point and artwork tiles, so the widget never draws a
/// second copy of the tile.
struct ProgramArtwork: View {
    let entry: NowPlayingTimelineEntry
    let size: CGFloat

    var body: some View {
        if let headline = entry.headline {
            Group {
                if let logo = entry.programLogo {
                    logo.resizable().scaledToFill()
                } else {
                    SpecialtyTileView(program: headline.program)
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .cornerRadius(size / 8)
        }
    }
}
