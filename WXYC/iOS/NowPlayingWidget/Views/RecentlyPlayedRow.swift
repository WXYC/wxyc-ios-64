//
//  RecentlyPlayedRow.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
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
            
            VStack(alignment: .leading) {
                Text(nowPlayingItem.playcut.artistName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Text(nowPlayingItem.playcut.songTitle)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.lighten)
        .cornerRadius(10)
        .clipped()
    }
    
    var artwork: some View {
        Group {
            if let artwork = nowPlayingItem.artwork {
                Image(uiImage: artwork)
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
            } else {
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
}

