//
//  RadioPlayerController.swift
//  WXYC
//
//  Created by Jake Bromberg on 8/2/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer

public enum PlaybackState {
    case playing
    case paused
}

public final class RadioPlayerController {
    public typealias PlaybackStateObserver = (PlaybackState) -> ()
    
    public convenience init() {
        self.init(radioPlayer: RadioPlayer())
    }
    
    init(
        radioPlayer: RadioPlayer = RadioPlayer(),
        notificationCenter: NotificationCenter = .default,
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.radioPlayer = radioPlayer
        
        self.inputObservations = [
            notificationCenter.addObserver(
                forName: .UIApplicationDidEnterBackground,
                object: nil,
                queue: nil,
                using: self.applicationDidEnterBackground
            ),
            notificationCenter.addObserver(
                forName: .UIApplicationWillEnterForeground,
                object: nil,
                queue: nil,
                using: self.applicationWillEnterForeground
            ),
            notificationCenter.addObserver(
                forName: .AVAudioSessionInterruption,
                object: nil,
                queue: nil,
                using: self.sessionInterrupted
            ),
            notificationCenter.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: nil,
                queue: nil,
                using: self.playbackStalled
            ),
            remoteCommandCenter.playCommand.addTarget(
                handler: self.remotePlayCommand
            ),
            remoteCommandCenter.pauseCommand.addTarget(
                handler: self.remotePauseOrStopCommand
            ),
            remoteCommandCenter.stopCommand.addTarget(
                handler: self.remotePauseOrStopCommand
            ),
            remoteCommandCenter.togglePlayPauseCommand.addTarget(
                handler: self.remotePauseOrStopCommand
            ),
        ]
    }
    
    // MARK: Public methods
    
    public func play() {
        try? AVAudioSession.sharedInstance().setActive(true)
        self.radioPlayer.play()
        self.playbackStateObserver?(.playing)
    }
    
    public func pause() {
        self.radioPlayer.pause()
        self.playbackStateObserver?(.paused)
    }
    
    public func observePlaybackState(_ observer: @escaping PlaybackStateObserver) {
        self.playbackStateObserver = observer
    }
    
    // MARK: Private
    
    private let radioPlayer: RadioPlayer
    
    private var inputObservations: [Any]? = nil
    
    private var playbackStateObserver: PlaybackStateObserver?
    
    // MARK: External Playback Command handlers
    
    @objc private func playbackStalled(_ notification: Notification) {
        // Have you tried switching it off and back on?
        self.radioPlayer.pause()
        self.radioPlayer.play()
    }
    
    @objc func sessionInterrupted(notification: Notification) {
        if notification.isAudioInterruptionBegan {
            self.pause()
        } else {
            self.play()
        }
    }
    
    // MARK: External playback command handlers
    
    @objc func applicationDidEnterBackground(notification: Notification) {
        guard !self.radioPlayer.isPlaying else {
            return
        }
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    @objc func applicationWillEnterForeground(notification: Notification) {
        if self.radioPlayer.isPlaying {
            self.play()
        } else {
            self.playbackStateObserver?(.paused)
        }
    }
    
    @objc func remotePlayCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        self.play()

        return .success
    }
    
    @objc func remotePauseOrStopCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        self.pause()

        return .success
    }
    
    @objc func remoteTogglePlayPauseCommand(command: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if self.radioPlayer.isPlaying {
            self.pause()
        } else {
            self.play()
        }
        
        return .success
    }
}

fileprivate extension Notification {
    var isAudioInterruptionBegan: Bool {
        guard let typeValue = self.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber else {
            return false
        }
        
        guard let type = AVAudioSessionInterruptionType(rawValue: typeValue.uintValue) else {
            return false
        }
        
        guard let _ = self.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
            return false
        }
        
        return type == .began
    }
}
