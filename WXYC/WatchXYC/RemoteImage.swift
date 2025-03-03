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
    @State var artwork: UIImage?
    
    init(playcut: Playcut) {
        self.playcut = playcut
    }

    var body: some View {
        Group {
            if let artwork {
                Image(uiImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image("logo", bundle: .main)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .task {
                        self.artwork = await ArtworkService.shared.getArtwork(for: playcut)
                    }
            }
        }
    }
    
    // MARK: Private
    
    let playcut: Playcut
}
