//
//  RecentlyPlayedRow.swift
//  WXYC
//
//  Row view for recently played tracks.
//
//  Created by Jake Bromberg on 11/25/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AppServices
import Playlist
import SwiftUI

struct RecentlyPlayedRow: View {
    let nowPlayingItem: NowPlayingItem
    let imageDimension: CGFloat = 45.0
    
    init(nowPlayingItem: NowPlayingItem) {
        self.nowPlayingItem = nowPlayingItem
    }
    
    var body: some View {
        HStack(alignment: .center) {
            artwork

            SongInfoColumn(
                song: nowPlayingItem.playcut,
                leadingField: .artistName,
                leadingFont: .headline,
                trailingFont: .subheadline,
                leadingLineLimit: 1,
                trailingLineLimit: 1,
                spacing: nil
            ) { EmptyView() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.lighten)
        .cornerRadius(10)
        .clipped()
    }

    /// Both branches occupy the same box, so the frame and padding are applied
    /// once to the `Group` rather than restated per branch.
    var artwork: some View {
        Group {
            if let artwork = nowPlayingItem.artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(10)
                    .clipped()
            } else {
                Image.logo
            }
        }
        .frame(
            width: imageDimension,
            height: imageDimension,
            alignment: .leading
        )
        .padding(5)
    }
}
