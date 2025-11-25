//
//  Header.swift
//  NowPlayingWidget
//
//  Copyright © 2022 WXYC. All rights reserved.
//

import SwiftUI

struct Header: View {
    var entry: NowPlayingTimelineEntry
    
    var body: some View {
        HStack(alignment: .center) {
            if let artwork = entry.artwork {
                artwork
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(10)
                    .frame(width: 100, height: 100)
            } else {
                Image.logo
                    .frame(width: 100, height: 100, alignment: .leading)
            }
            
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
                    .frame(alignment: .bottom)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

