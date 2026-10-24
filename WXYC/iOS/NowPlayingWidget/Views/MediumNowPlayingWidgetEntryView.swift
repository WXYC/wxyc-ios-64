//
//  MediumNowPlayingWidgetEntryView.swift
//  WXYC
//
//  Medium widget family layout.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import WidgetKit

struct MediumNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    var entry: NowPlayingTimelineEntry
    
    var body: some View {
        ZStack(alignment: .leading) {
            background
            
            HStack(alignment: .center) {
                if entry.programLeads {
                    ProgramArtwork(entry: entry, size: 90)
                } else {
                    self.artwork
                        .cornerRadius(10)
                        .aspectRatio(contentMode: .fit)
                }

                VStack(alignment: .leading) {
                    if entry.programLeads, let headline = entry.headline {
                        Text(headline.program.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(headline.person)
                            .font(.subheadline)
                            .lineLimit(1)
                        if let tagline = headline.tagline {
                            Text(tagline)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    } else {
                        if let headline = entry.headline {
                            // The program line: an 18-point tile above the artist while one of its songs is current.
                            HStack(spacing: 4) {
                                ProgramArtwork(entry: entry, size: 18)
                                Text(headline.program.name).font(.caption).lineLimit(1)
                            }
                        }
                        SongInfoColumn(
                            song: entry,
                            leadingField: .artistName,
                            leadingFont: .headline,
                            trailingFont: .subheadline,
                            leadingLineLimit: 1,
                            trailingLineLimit: 1,
                            spacing: nil
                        ) { EmptyView() }
                    }

                    PlayButton()
                }
            }
        }
        .safeAreaPadding()
        .containerBackground(Color.clear, for: .widget)
    }
}
