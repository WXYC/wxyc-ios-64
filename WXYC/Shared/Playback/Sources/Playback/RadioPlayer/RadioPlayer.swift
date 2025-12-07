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
import Core
import Caching
import PostHog
import Analytics

@MainActor
@Observable
internal final class RadioPlayer: Sendable {
    private let streamURL: URL
    private var playerObservation: (any NSObjectProtocol)?
    private var timer: Core.Timer = Core.Timer.start()
    private let userDefaults: UserDefaults
    private let analytics: AnalyticsService?
    private let notificationCenter: NotificationCenter

    convenience init(streamURL: URL = RadioStation.WXYC.streamURL) {
        self.init(
            streamURL: streamURL,
            player: AVPlayer(url: streamURL),
            userDefaults: .wxyc,
            analytics: PostHogAnalytics.shared,
            notificationCenter: .default
        )
    }

    init(
        streamURL: URL = RadioStation.WXYC.streamURL,
        player: PlayerProtocol,
        userDefaults: UserDefaults,
        analytics: AnalyticsService? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.streamURL = streamURL
        self.player = player
        self.userDefaults = userDefaults
        self.analytics = analytics
        self.notificationCenter = notificationCenter
        
        self.playerObservation =
        notificationCenter.addObserver(
            forName: AVPlayer.rateDidChangeNotification,
            object: player as? AVPlayer,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            Log(.info, "RadioPlayer did receive notification", notification)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPlaying = self.player.rate > 0
                if self.isPlaying {
                    let timeToAudio = self.timer.duration()
                    self.analytics?.capture("Time to first Audio", properties: [
                        "timeToAudio": timeToAudio
                    ])
                }
            }
        }
    }

    private(set) var isPlaying = false
    
    func play() {
        if self.isPlaying {
            analytics?.capture("already playing (local)")
            return
        }
        
        // Mark as playing in shared UserDefaults
        userDefaults.set(true, forKey: "isPlaying")

        analytics?.capture("radioPlayer play")
        timer = Timer.start()
        self.player.play()
    }

    func pause() {
        userDefaults.set(false, forKey: "isPlaying")
        
        // Notify other processes that we're stopping playback
        self.player.pause()
        self.resetStream()
    }

    // MARK: Private

    private let player: PlayerProtocol
    
    private func resetStream() {
        let asset = AVURLAsset(url: self.streamURL)
        let playerItem = AVPlayerItem(asset: asset)
        self.player.replaceCurrentItem(with: playerItem)
    }
}
