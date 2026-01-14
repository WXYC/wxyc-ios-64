//
//  SoundPlayer.swift
//  PartyHorn
//
//  Audio player for party horn sound effects.
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AVFoundation

@MainActor
final class SoundPlayer {
    private var player: AVAudioPlayer?
    
    init() {
        guard let url = Bundle.module.url(forResource: "airhorn", withExtension: "mp3") else {
            return
        }

        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = 0
        player?.prepareToPlay()
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        if !player.isPlaying {
            player.stop()
            player.play()
        }
    }
}
