//
//  RemoteImage.swift
//  WatchXYC App
//
//  Created by Jake Bromberg on 2/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import SwiftUI
import Core

struct RemoteImage: View {
    let playcut: Playcut
    let placeholder: Image = Image(systemName: "photo")
    @State var artFetcher: AlbumArtworkFetcher
    @State var artwork: UIImage?
    
    init(playcut: Playcut, contentMode: ContentMode = .fit) {
        self.playcut = playcut
        self.artFetcher = AlbumArtworkFetcher(playcut: playcut)
    }

    var body: some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholder.renderingMode(.original)
            }
        }
        .task {
            artwork = await artFetcher.fetchArtwork()
        }
    }
}
