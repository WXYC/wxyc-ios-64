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
                    SongInfoColumn(
                        song: entry,
                        leadingField: .artistName,
                        leadingFont: .headline,
                        trailingFont: .subheadline,
                        leadingLineLimit: 1,
                        trailingLineLimit: 1,
                        spacing: nil
                    ) { EmptyView() }

                    PlayButton()
                }
            }
        }
        .safeAreaPadding()
        .containerBackground(Color.clear, for: .widget)
    }
}
