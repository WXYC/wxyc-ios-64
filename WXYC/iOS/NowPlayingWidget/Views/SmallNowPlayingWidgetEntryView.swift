//
//  SmallNowPlayingWidgetEntryView.swift
//  WXYC
//
//  Small widget family layout.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
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

                SongInfoColumn(
                    song: entry,
                    leadingField: .artistName,
                    leadingFont: .caption,
                    trailingFont: .caption,
                    leadingLineLimit: 1,
                    trailingLineLimit: 1
                ) { EmptyView() }

                PlayButton()
            }
        }
        .containerBackground(Color.clear, for: .widget)
        .safeAreaPadding()
    }
}
