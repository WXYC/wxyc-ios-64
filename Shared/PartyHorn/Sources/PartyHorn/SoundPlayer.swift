//
//  SoundPlayer.swift
//  Party Horn
//
//  Created by Jake Bromberg on 8/13/25.
//

import AVFoundation

@MainActor
final class SoundPlayer {
    private var player: AVAudioPlayer
    
    init() {
        try! AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try! AVAudioSession.sharedInstance().setActive(true)
        
        guard let url = Bundle.module.url(forResource: "airhorn", withExtension: "mp3") else {
            fatalError("Failed to find airhorn.mp3 resource in bundle")
        }
        
        player = try! AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = 0
        player.prepareToPlay()
    }
    
    func play() {
        player.currentTime = 0
        if !player.isPlaying {
            player.stop()
            player.play()
        }
    }
}
