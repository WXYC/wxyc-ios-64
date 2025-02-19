//
//  RadioPlayer.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/1/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import AVFoundation

@MainActor
internal final class RadioPlayer: Sendable {
    private let streamURL: URL
    private var playerObservation: (any NSObjectProtocol)?
    
    init(streamURL: URL = .WXYCStream128kMP3) {
        self.streamURL = streamURL
        self.player = AVPlayer(url: streamURL)
        self.playerObservation =
            NotificationCenter.default.addObserver(
                forName: AVPlayer.rateDidChangeNotification,
                object: self.player,
                queue: nil
            ) { notification in
                print(notification)
                Task { @MainActor in
                    self.isPlaying = self.player.rate > 0
                    self.playbackState = self.isPlaying ? .playing : .paused
                }
            }
    }
    
    @Publishable var isPlaying: Bool = false
    
    var playbackState: PlaybackState = .initialized
    
    func play() {
        if self.isPlaying {
            return
        }
        
        try? AVAudioSession.sharedInstance().setActive(true)
        
        player.play()
    }
    
    func pause() {
        player.pause()
        self.resetStream()
    }
    
    // MARK: Private
    
    private let player: AVPlayer
    
    private func resetStream() {
        let asset = AVURLAsset(url: self.streamURL)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
    }
}

private extension AVPlayer {
    var isPlaying: Bool {
        return rate > 0.0
    }
}
