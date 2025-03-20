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
                    await loadArtwork()
                }
            }
    }

    private func loadArtwork() async {
        if let newArtwork = await ArtworkService.shared.getArtwork(for: playcut) {
            self.artwork = newArtwork
        }
    }
}
