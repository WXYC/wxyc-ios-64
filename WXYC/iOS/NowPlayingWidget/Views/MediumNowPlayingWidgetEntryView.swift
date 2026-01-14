//
//  MediumNowPlayingWidgetEntryView.swift
//  WXYC
//
//  Medium widget family layout.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import WidgetKit

struct MediumNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    var entry: NowPlayingTimelineEntry
    
    var body: some View {
        ZStack(alignment: .leading) {
            background
            
            HStack(alignment: .center) {
                self.artwork
                    .cornerRadius(10)
                    .aspectRatio(contentMode: .fit)
                
                VStack(alignment: .leading) {
                    Text(entry.artist)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(entry.songTitle)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    PlayButton()
                        .background(Capsule().fill(Color.red))
                        .clipped()
                    
                }
            }
        }
        .safeAreaPadding()
        .containerBackground(Color.clear, for: .widget)
    }
}
