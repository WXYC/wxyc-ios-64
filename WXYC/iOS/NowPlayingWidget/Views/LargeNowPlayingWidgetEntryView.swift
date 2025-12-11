//
//  LargeNowPlayingWidgetEntryView.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
//

import SwiftUI
import WidgetKit

struct LargeNowPlayingWidgetEntryView: NowPlayingWidgetEntryView {
    let entry: NowPlayingTimelineEntry
    
    init(entry: NowPlayingTimelineEntry) {
        self.entry = entry
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            background
            
            VStack(alignment: .leading, spacing: 10) {
                Spacer()
                
                Header(entry: entry)

                Text("Recently Played")
                    .font(.body.smallCaps().bold())
                    .foregroundStyle(.white)
                    .frame(maxHeight: .infinity, alignment: .top)
                
                ForEach(entry.recentItems, id: \.playcut.chronOrderID) { nowPlayingItem in
                    RecentlyPlayedRow(nowPlayingItem: nowPlayingItem)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                
                Spacer()
            }
            .safeAreaPadding()
        }
        .containerBackground(Color.clear, for: .widget)
    }
}

