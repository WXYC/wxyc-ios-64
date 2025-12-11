//
//  NowPlayingWidgetEntryView.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
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
        Group {
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
    }
    
    @ViewBuilder
    var background: some View {
        Image.background
        
        Color.darken
            .ignoresSafeArea()
    }
}

