//
//  RadioPlayer.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/1/17.
//  Copyright © 2017 wxyc.org. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import Logger
import PostHog

@MainActor
internal final class RadioPlayer: Sendable {
    private let streamURL: URL
    private var playerObservation: (any NSObjectProtocol)?
    private var timer: Timer = Timer.start()
    
    init(streamURL: URL = .WXYCStream128kMP3) {
        self.streamURL = streamURL
        self.player = AVPlayer(url: streamURL)
        self.playerObservation =
            NotificationCenter.default.addObserver(
                forName: AVPlayer.rateDidChangeNotification,
                object: self.player,
                queue: nil
            ) { notification in
                Log(.info, "RadioPlayer did receive notification", notification)
                Task { @MainActor in
                    self.isPlaying = self.player.rate > 0
                }
            }
    }
    
    public var isPlaying = false {
        didSet {
            for o in observers {
                o(self.isPlaying)
            }
        }
    }
    
    public typealias Observer = @MainActor @Sendable (Bool) -> ()
    @MainActor private var observers: [Observer] = []
    
    @MainActor
    public func observe(_ observer: @escaping Observer) {
        Task { @MainActor in
            observer(self.isPlaying)
            self.observers.append(observer)
        }
    }
        
    func play() {
        if self.isPlaying {
            PostHogSDK.shared.capture("already playing")
            return
        }
        UserDefaults.wxyc.set(true, forKey: "isPlaying")
        print(">>>> \(UserDefaults.wxyc.bool(forKey: "isPlaying"))")
        
        PostHogSDK.shared.capture("play")
        timer = Timer.start()
        self.player.play()
    }
    
    func pause() {
        UserDefaults.wxyc.set(false, forKey: "isPlaying")
        print(">>>> \(UserDefaults.wxyc.bool(forKey: "isPlaying"))")
        player.pause()
        self.resetStream()
    }
    
    // MARK: Private
    
    private let player: AVPlayer
    
    private func resetStream() {
        let asset = AVURLAsset(url: self.streamURL)
        let playerItem = AVPlayerItem(asset: asset)
        self.player.replaceCurrentItem(with: playerItem)
        self.player.pause()
    }
}

private extension AVPlayer {
    var isPlaying: Bool {
        return rate > 0.0
    }
}
