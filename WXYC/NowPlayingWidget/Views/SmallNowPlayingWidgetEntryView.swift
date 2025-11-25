//
//  SmallNowPlayingWidgetEntryView.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
//

import SwiftUI
import WidgetKit

struct SmallNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    var entry: NowPlayingTimelineEntry
    
    var body: some View {
        ZStack(alignment: .leading) {
            background
            
            VStack(alignment: .leading) {
                self.artwork
                
                Text(entry.artist)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(entry.songTitle)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                PlayButton()
                    .background(Capsule().fill(Color.red))
                    .clipped()
            }
        }
        .containerBackground(Color.clear, for: .widget)
        .safeAreaPadding()
    }
}

