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
                trailingLineLimit: 1
            ) { EmptyView() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.lighten)
        .cornerRadius(10)
        .clipped()
    }

    var artwork: some View {
        artworkOrLogo(nowPlayingItem.artwork.map(Image.init(uiImage:))) { artwork in
            artwork
                .resizable()
                .aspectRatio(contentMode: .fit)
                .cornerRadius(10)
                .clipped()
                .frame(
                    width: imageDimension,
                    height: imageDimension,
                    alignment: .leading
                )
                .padding(5)
        } fallback: {
            Image.logo
                .frame(
                    width: imageDimension,
                    height: imageDimension,
                    alignment: .leading
                )
                .padding(5)
        }
    }
}
