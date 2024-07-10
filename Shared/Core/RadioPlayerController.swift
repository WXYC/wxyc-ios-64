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

@MainActor
public final class RadioPlayerController {
    public static let shared = RadioPlayerController()
    
    private init(
        radioPlayer: RadioPlayer = RadioPlayer(),
        notificationCenter: NotificationCenter = .default,
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.radioPlayer = radioPlayer
        
        func notificationObserver(for name: Notification.Name, sink: @escaping (Notification) -> ()) -> Any {
            return notificationCenter.publisher(for: name)
                .sink(receiveValue: sink)
        }
        
        func remoteCommandObserver(
            for command: KeyPath<MPRemoteCommandCenter, MPRemoteCommand>,
            handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
        ) -> Any {
            return remoteCommandCenter[keyPath: command].addTarget(handler: handler)
        }
        
        self.inputObservations = [
            notificationObserver(for: UIApplication.didEnterBackgroundNotification, sink: self.applicationDidEnterBackground),
            notificationObserver(for: UIApplication.willEnterForegroundNotification, sink: self.applicationWillEnterForeground),
            notificationObserver(for: AVAudioSession.interruptionNotification, sink: self.sessionInterrupted),
            notificationObserver(for: .AVPlayerItemPlaybackStalled, sink: self.playbackStalled),
            
            remoteCommandObserver(for: \.playCommand, handler: self.remotePlayCommand),
            remoteCommandObserver(for: \.pauseCommand, handler: self.remotePauseOrStopCommand),
            remoteCommandObserver(for: \.stopCommand, handler: self.remotePauseOrStopCommand),
            remoteCommandObserver(for: \.togglePlayPauseCommand, handler: self.remotePauseOrStopCommand),
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
    
    // MARK: Private
    
    private let radioPlayer: RadioPlayer
    
    private var inputObservations: [Any]? = nil
    
    @Published public var playbackState: PlaybackState = .paused {
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
        }
    }
}

private extension RadioPlayerController {
    // MARK: AVPlayer handlers
    
    func playbackStalled(_ notification: Notification) {
        // Have you tried turning it off and on again?
        self.radioPlayer.pause()
        self.radioPlayer.play()
    }
    
    func sessionInterrupted(notification: Notification) {
        if notification.isAudioInterruptionBegan {
            self.pause()
        } else {
            self.play()
        }
    }
    
    // MARK: External playback command handlers
    
    func applicationDidEnterBackground(notification: Notification) {
        guard !self.radioPlayer.isPlaying else {
            return
        }
        
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    func applicationWillEnterForeground(notification: Notification) {
        if self.radioPlayer.isPlaying {
            self.play()
        } else {
            self.pause()
        }
    }
    
    func remotePlayCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        self.play()

        return .success
    }
    
    func remotePauseOrStopCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        self.pause()

        return .success
    }
    
    func remoteTogglePlayPauseCommand(command: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
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
