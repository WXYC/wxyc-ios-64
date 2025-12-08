//
//  RemoteImage.swift
//  WatchXYC App
//
//  Created by Jake Bromberg on 2/27/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import SwiftUI
import Playlist
import Artwork

struct RemoteImage: View {
    @State var artwork: UIImage = UIImage(named: "logo")!
    private let playcut: Playcut

    init(playcut: Playcut) {
        self.playcut = playcut
    }

    var body: some View {
        Image(uiImage: artwork)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .transition(.opacity)
            .onChange(of: playcut, initial: true) {
                Task {
                    try await loadArtwork()
                }
            }
    }

    private func loadArtwork() async throws {
        self.artwork = try await MultisourceArtworkService().fetchArtwork(for: playcut)
    }
}
