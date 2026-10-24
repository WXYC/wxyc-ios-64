//
//  SmallNowPlayingWidgetEntryView.swift
//  WXYC
//
//  Small widget family layout.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import WidgetKit

struct SmallNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    var entry: NowPlayingTimelineEntry
    
    var body: some View {
        ZStack(alignment: .leading) {
            background
            
            VStack(alignment: .leading) {
                if entry.programLeads, let headline = entry.headline {
                    ProgramArtwork(entry: entry, size: 56)
                    Text(headline.program.name)
                        .font(.caption.bold())
                        .lineLimit(2)
                    Text(headline.person)
                        .font(.caption)
                        .lineLimit(1)
                } else {
                    // A song from a specialty show carries the program's tile or logo as a corner badge.
                    self.artwork
                        .overlay(alignment: .topTrailing) {
                            ProgramArtwork(entry: entry, size: 24).padding(4)
                        }

                    SongInfoColumn(
                        song: entry,
                        leadingField: .artistName,
                        leadingFont: .caption,
                        trailingFont: .caption,
                        leadingLineLimit: 1,
                        trailingLineLimit: 1,
                        spacing: nil
                    ) { EmptyView() }
                }

                PlayButton()
            }
        }
        .containerBackground(Color.clear, for: .widget)
        .safeAreaPadding()
    }
}
