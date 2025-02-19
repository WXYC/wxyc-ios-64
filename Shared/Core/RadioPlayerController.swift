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

public enum PlaybackState: Sendable {
    case initialized
    case playing
    case paused
}

public final class RadioPlayerController: @unchecked Sendable {
    @MainActor
    public static let shared = RadioPlayerController()
    
    private var radioPlayerObservation: Any! = nil

    @MainActor
    private init(
        radioPlayer: RadioPlayer = RadioPlayer(),
        notificationCenter: NotificationCenter = .default,
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        try? AVAudioSession.sharedInstance().setActive(true)
        
        func notificationObserver(
            for name: Notification.Name,
            sink: @escaping @Sendable @MainActor (Notification) -> ()
        ) -> any Sendable {
            let wrappedSink = { (notification: Notification) in
                let _ = Task { @MainActor in
                    sink(notification)
                }
            }
            
            return NonSendableBox<NSObjectProtocol>(
                value: notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: nil,
                    using: wrappedSink
                )
            )
        }
        
        func remoteCommandObserver(
            for command: KeyPath<MPRemoteCommandCenter, MPRemoteCommand>,
            handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
        ) -> any Sendable {
            NonSendableBox<Any>(
                value: remoteCommandCenter[keyPath: command].addTarget(handler: handler)
            )
        }

        self.radioPlayer = radioPlayer

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
        
        self.radioPlayer.$isPlaying.observe { isPlaying in
            self.isPlaying = isPlaying
        }
    }
    
    // MARK: Public methods
    
    public func toggle() {
        Task { @MainActor in
            self.radioPlayer.isPlaying
                ? self.radioPlayer.pause()
                : self.radioPlayer.play()
        }
    }
    
    public func play() {
        Task { @MainActor in
            self.radioPlayer.play()
        }
    }
    
    public func pause() {
        Task { @MainActor in
            self.radioPlayer.pause()
        }
    }
    
    // MARK: Private
    
    private let radioPlayer: RadioPlayer
    private var inputObservations: [any Sendable]? = nil
    
    @Publishable var playbackState: PlaybackState! = .initialized
    @Publishable public var isPlaying = false
}

private extension RadioPlayerController {
    // MARK: AVPlayer handlers
    
    func playbackStalled(_ notification: Notification) {
        Task { @MainActor in
            // Have you tried turning it off and on again?
            self.radioPlayer.pause()
            self.radioPlayer.play()
        }
    }
    
    func sessionInterrupted(notification: Notification) {
        guard let interruptionType = notification.interruptionType else {
            return
        }
        
        switch interruptionType {
        case .began:
            self.play()
        case .shouldResume:
            self.pause()
        case .ended:
            return
        }
    }
    
    // MARK: External playback command handlers
    
    func applicationDidEnterBackground(notification: Notification) {
        Task { @MainActor in
            guard !self.radioPlayer.isPlaying else {
                return
            }
            
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }
    
    func applicationWillEnterForeground(notification: Notification) {
        Task { @MainActor in
            if self.radioPlayer.isPlaying {
                self.play()
            } else {
                self.pause()
            }
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
    
    @MainActor
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
    var interruptionType: InterruptionType? {
        guard let typeValue = self.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber else {
            return nil
        }
        
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue.uintValue) else {
            return nil
        }
        
        guard let _ = self.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
            return nil
        }
        
        if type == .began {
            return .began
        }
        
        guard let optionsValue = self.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt else {
          return nil
        }
        
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
            return .shouldResume
        }

        return nil
    }
}

enum InterruptionType {
    case began
    case ended
    case shouldResume
}

struct NonSendableBox<NonSendableType>: @unchecked Sendable {
    let value: NonSendableType
}
