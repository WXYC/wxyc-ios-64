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
import Logger
import UIKit

public enum PlaybackState: Sendable {
    case initialized
    case playing
    case paused
}

@MainActor
public final class RadioPlayerController: @unchecked Sendable {
    public static let shared = RadioPlayerController()
    
    @Publishable public var isPlaying = false

    private init(
        radioPlayer: RadioPlayer = RadioPlayer(),
        notificationCenter: NotificationCenter = .default,
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        func notificationObserver(
            for name: Notification.Name,
            sink: @escaping @Sendable @isolated(any) (Notification) -> ()
        ) -> any Sendable {
            NonSendableBox<NSObjectProtocol>(
                value: notificationCenter.addObserver(
                    forName: name,
                    object: nil,
                    queue: nil,
                    using: sink
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
#if os(iOS)
        self.inputObservations = [
            notificationObserver(for: UIApplication.didEnterBackgroundNotification, sink: self.applicationDidEnterBackground),
            notificationObserver(for: UIApplication.willEnterForegroundNotification, sink: self.applicationWillEnterForeground),
        ]
#endif

        self.inputObservations += [
            notificationObserver(for: AVAudioSession.interruptionNotification, sink: self.sessionInterrupted),
            notificationObserver(for: .AVPlayerItemPlaybackStalled, sink: self.playbackStalled),
            
            remoteCommandObserver(for: \.playCommand, handler: self.remotePlayCommand),
            remoteCommandObserver(for: \.pauseCommand, handler: self.remotePauseOrStopCommand),
            remoteCommandObserver(for: \.stopCommand, handler: self.remotePauseOrStopCommand),
            remoteCommandObserver(for: \.togglePlayPauseCommand, handler: self.remotePauseOrStopCommand),
        ]
        
        self.radioPlayer.$isPlaying.observe { @MainActor isPlaying in
            self.isPlaying = isPlaying
        }
    }
    
    // MARK: Public methods
    
    public func toggle() {
        self.radioPlayer.isPlaying
            ? self.radioPlayer.pause()
            : self.radioPlayer.play()
    }
    
    public func play() {
        do {
            try AVAudioSession.shared.activate()
        } catch {
            Log(.error, "RadioPlayerController could not start playback: \(error)")
        }
        
        self.radioPlayer.play()
    }
    
    public func pause() {
        self.radioPlayer.pause()
    }
    
    // MARK: Private
    
    private let radioPlayer: RadioPlayer
    private var inputObservations: [any Sendable] = []

    @Publishable var playbackState: PlaybackState! = .initialized
}

private extension RadioPlayerController {
    // MARK: AVPlayer handlers
    
    func playbackStalled(_ notification: Notification) {
        Log(.error, "Playback stalled: \(notification)")
        // Turn it off and on again.
        self.radioPlayer.pause()
        self.radioPlayer.play()
    }
    
    func sessionInterrupted(notification: Notification) {
        Log(.info, "Session interrupted: \(notification)")
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
        guard !self.radioPlayer.isPlaying else {
            return
        }
        
        do {
            try AVAudioSession.shared.deactivate()
        } catch {
            Log(.error, "RadioPlayerController could not deactivate: \(error)")
        }
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
    var interruptionType: InterruptionType? {
        guard let typeValue = self.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber else {
            Log(.error, "Could not extract interruption type from notification")
            return nil
        }
        
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue.uintValue) else {
            Log(.error, "Could not convert interruption type to AVAudioSession.InterruptionType")
            return nil
        }
        
        guard let _ = self.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else {
            Log(.error, "Could not extract interruption options from notification")
            return nil
        }
        
        if type == .began {
            return .began
        }
        
        guard let optionsValue = self.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt else {
            Log(.error, "Could not extract interruption options from notification")
            return nil
        }
        
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
            return .shouldResume
        }
        
        Log(.error, "Unsupported interruption type: \(type) with options: \(options)")
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

extension AVAudioSession {
    static var shared: AVAudioSession {
        return AVAudioSession.sharedInstance()
    }
    
    func activate() throws {
        try setActive(true)
    }
    
    func deactivate() throws {
        try setActive(false)
    }
}
