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
    var artwork: some View {
        artworkOrLogo(entry.artwork) { artwork in
            artwork
                .resizable()
                .frame(maxWidth: 800, maxHeight: 800)
                .aspectRatio(contentMode: .fit)
                .cornerRadius(5)
        } fallback: {
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
