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
    
    public static let shared = RadioPlayerController()
    
    private convenience init() {
        self.init(radioPlayer: RadioPlayer())
    }
    
    private init(
        radioPlayer: RadioPlayer = RadioPlayer(),
        notificationCenter: NotificationCenter = .default,
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.radioPlayer = radioPlayer
        
        self.inputObservations = [
            notificationCenter.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: nil,
                using: self.applicationDidEnterBackground
            ),
            notificationCenter.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil,
                using: self.applicationWillEnterForeground
            ),
            notificationCenter.addObserver(
                forName: AVAudioSession.interruptionNotification,
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
    
    public func toggle() {
        switch self.playbackState {
        case .paused:
            self.playbackState = .playing
        case .playing:
            self.playbackState = .paused
        }
    }
    
    public func play() {
        self.playbackState = .playing
    }
    
    public func pause() {
        self.playbackState = .paused
    }
    
    public func observePlaybackState(_ observer: @escaping PlaybackStateObserver) {
        self.playbackStateObservers.append(observer)
        observer(self.playbackState)
    }
    
    // MARK: Private
    
    private let radioPlayer: RadioPlayer
    
    private var inputObservations: [Any]? = nil
    
    private var playbackState: PlaybackState = .paused {
        didSet {
            guard oldValue != self.playbackState else {
                return
            }
            
            switch self.playbackState {
            case .playing:
                try? AVAudioSession.sharedInstance().setActive(true)
                self.radioPlayer.play()
            case .paused:
                self.radioPlayer.pause()
            }
            
            self.updateObservers(self.playbackState)
        }
    }
    
    private var playbackStateObservers: [PlaybackStateObserver] = []
    
    private func updateObservers(_ state: PlaybackState) {
        for observer in self.playbackStateObservers {
            observer(state)
        }
    }
    
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
            self.pause()
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
        
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue.uintValue) else {
            return false
        }
        
        guard let _ = self.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
            return false
        }
        
        return type == .began
    }
}
