//
//  SoundPlayer.swift
//  Party Horn
//
//  Created by Jake Bromberg on 8/13/25.
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
