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

protocol AudioSessionConfiguring {
    func setCategory(
        _ category: AVAudioSession.Category,
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions
    ) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: AudioSessionConfiguring {}

@MainActor
final class SoundPlayer {
    private var player: AVAudioPlayer?
    private let audioSession: AudioSessionConfiguring

    init(audioSession: AudioSessionConfiguring = AVAudioSession.sharedInstance()) {
        self.audioSession = audioSession

        guard let url = Bundle.module.url(forResource: "airhorn", withExtension: "mp3") else {
            return
        }

        player = try? AVAudioPlayer(contentsOf: url)
        player?.numberOfLoops = 0
        player?.prepareToPlay()
    }

    func play() {
        // Activate .playback so the sound overrides the silent switch. Mix with
        // others so the radio stream (and any other app's audio) keeps playing.
        try? audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? audioSession.setActive(true, options: [])

        guard let player else { return }
        player.currentTime = 0
        if !player.isPlaying {
            player.stop()
            player.play()
        }
    }
}
