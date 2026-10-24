//
//  LargeNowPlayingWidgetEntryView.swift
//  WXYC
//
//  Large widget family layout.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import WidgetKit
import AppServices
import Playlist

struct LargeNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    /// The side, in points, of the art slot a specialty program's logo or tile fills (and the poster, #1180).
    static let artSlot: CGFloat = 120

    let entry: NowPlayingTimelineEntry
    
    init(entry: NowPlayingTimelineEntry) {
        self.entry = entry
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            background
            
            VStack(alignment: .leading, spacing: 10) {
                Spacer()

                if entry.programLeads, let headline = entry.headline {
                    programHero(headline)
                } else {
                    if let headline = entry.headline {
                        programCard(headline)
                    }
                    if let guestLine = entry.guestLine {
                        Text(guestLine).font(.subheadline).lineLimit(1).foregroundStyle(.white)
                    }
                    Header(entry: entry)
                }

                Text(entry.recentsLabel)
                    .font(.body.smallCaps().bold())
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity, alignment: .top)
                
                // `id` (row identity), not `chronOrderID` (ordering only, and
                // no longer guaranteed unique post-#839 composite key).
                ForEach(entry.recentItems, id: \.playcut.id) { nowPlayingItem in
                    RecentlyPlayedRow(nowPlayingItem: nowPlayingItem)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                
                Spacer()
            }
            .safeAreaPadding()
        }
        .containerBackground(Color.clear, for: .widget)
    }

    /// No song from the open show yet: the program over the person, with its tagline.
    private func programHero(_ headline: NowPlayingHeadline) -> some View {
        HStack(alignment: .center) {
            ProgramArtwork(entry: entry, size: Self.artSlot)
            VStack(alignment: .leading) {
                Text(headline.program.name).font(.headline).lineLimit(2)
                Text(headline.person).font(.subheadline).lineLimit(1)
                if let supporting = entry.supportingLine {
                    Text(supporting).font(.caption).lineLimit(2)
                }
                PlayButton()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A song from the open show is current: the program's tile or logo, name and tagline above it.
    private func programCard(_ headline: NowPlayingHeadline) -> some View {
        HStack {
            ProgramArtwork(entry: entry, size: 40)
            VStack(alignment: .leading) {
                Text(headline.program.name).font(.subheadline.bold()).lineLimit(2)
                if let tagline = headline.tagline {
                    Text(tagline).font(.caption).lineLimit(1)
                }
            }
            .foregroundStyle(.white)
        }
    }
}
