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
import PostHog

public enum PlaybackState: Sendable {
    case initialized
    case playing
    case paused
}

@MainActor
public final class RadioPlayerController {
    public static let shared = RadioPlayerController()
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
            notificationObserver(for: AVAudioSession.routeChangeNotification, sink: self.routeChanged),
            notificationObserver(for: .AVPlayerItemPlaybackStalled, sink: self.playbackStalled),
            
            remoteCommandObserver(for: \.playCommand, handler: self.remotePlayCommand),
            remoteCommandObserver(for: \.pauseCommand, handler: self.remotePauseOrStopCommand),
            remoteCommandObserver(for: \.stopCommand, handler: self.remotePauseOrStopCommand),
            remoteCommandObserver(for: \.togglePlayPauseCommand, handler: self.remotePauseOrStopCommand),
        ]
        
        self.radioPlayer.observe { isPlaying in
            self.isPlaying = isPlaying
        }
    }
    
    // MARK: Public methods
    
    public func toggle() {
        if self.isPlaying {
            PostHogSDK.shared.pause(duration: playbackTimer.duration())
            self.pause()
        } else {
            self.play()
        }
    }
    
    private var audioActivationTask: Task<Bool, any Error>?
    
    public func play() {
        Task {
            do {
                self.playbackTimer = Timer.start()
                PostHogSDK.shared.play()
                
#if os(watchOS)
                let activated = try await AVAudioSession.sharedInstance().activate()
                if activated {
                    PostHogSDK.shared.play()
                    self.radioPlayer.play()
                } 
                
#else
                try AVAudioSession.shared.activate()
                self.radioPlayer.play()
#endif
            } catch {
                PostHogSDK.shared.capture(error: error, context: "RadioPlayerController could not start playback")
                Log(.error, "RadioPlayerController could not start playback: \(error)")
            }
        }
    }
    
    public func pause() {
        self.radioPlayer.pause()
    }
    
    // MARK: Private
    
    private let radioPlayer: RadioPlayer
    private var inputObservations: [any Sendable] = []
    
    private var playbackTimer = Timer.start()
    private var backoffTimer = ExponentialBackoff(initialWaitTime: 0.5, maximumWaitTime: 10.0)
}

private extension RadioPlayerController {
    // MARK: AVPlayer handlers
    
    func playbackStalled(_ notification: Notification) {
        Log(.error, "Playback stalled: \(notification)")
        PostHogSDK.shared.pause(duration: playbackTimer.duration())
        self.radioPlayer.pause()
        self.attemptReconnectWithExponentialBackoff()
    }
    
    func sessionInterrupted(notification: Notification) {
        Log(.info, "Session interrupted: \(notification)")
        guard let interruptionType = notification.interruptionType else {
            return
        }
        
        let interruptionReason = notification.interruptionReason
        let iterruptionOptions = notification.interruptionOptions
        
        switch interruptionType {
        case .began:
            // `.routeDisconnected` types are not balanced by a `.ended` notification.
            if interruptionReason == .routeDisconnected {
                PostHogSDK.shared.pause(duration: playbackTimer.duration(), reason: "route disconnected")
            } else if let options = iterruptionOptions,
                      options.contains(.shouldResume) {
                PostHogSDK.shared.pause(duration: playbackTimer.duration(), reason: "should resume")
            } else {
                PostHogSDK.shared.pause(duration: playbackTimer.duration(), reason: "no reason")
                self.pause()
            }
        case .shouldResume, .ended:
            PostHogSDK.shared.play()
            self.play()
        }
    }
    
    func routeChanged(notification: Notification) {
        // Use AVAudioSession.shared.currentRoute since the notification only provides the previous
        // audio output.
        Log(.info, "Session route changed: \(AVAudioSession.shared.currentRoute)")
        PostHogSDK.shared.capture("Audio session route changed", properties: [
            "current route" : String(describing: AVAudioSession.shared.currentRoute)
        ])
    }
    
    private func attemptReconnectWithExponentialBackoff() {
        let waitTime = self.backoffTimer.nextWaitTime()
        Log(.info, "Attempting to reconnect with exponential backoff \(self.backoffTimer).")
        Task {
            if self.radioPlayer.isPlaying {
                self.backoffTimer.reset()
                return
            }
            
            do {
                self.radioPlayer.play()
                try await Task.sleep(nanoseconds: waitTime.nanoseconds)
                
                if !radioPlayer.isPlaying {
                    attemptReconnectWithExponentialBackoff()
                } else {
                    self.backoffTimer.reset()
                }
            } catch {
                self.backoffTimer.reset()
                
                return
            }
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
            PostHogSDK.shared.capture(error: error, context: "RadioPlayerController could not deactivate")
            Log(.error, "RadioPlayerController could not deactivate: \(error)")
        }
    }
    
    func applicationWillEnterForeground(notification: Notification) {
        if self.radioPlayer.isPlaying {
            PostHogSDK.shared.play()
            self.play()
        } else {
            PostHogSDK.shared.pause(duration: playbackTimer.duration())
            self.pause()
        }
    }
    
    func remotePlayCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        PostHogSDK.shared.play()
        self.play()

        return .success
    }
    
    func remotePauseOrStopCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        PostHogSDK.shared.pause(duration: playbackTimer.duration())
        self.pause()

        return .success
    }
    
    func remoteTogglePlayPauseCommand(command: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if self.radioPlayer.isPlaying {
            PostHogSDK.shared.pause(duration: playbackTimer.duration())
            self.pause()
        } else {
            PostHogSDK.shared.play()
            self.play()
        }
        
        return .success
    }
}

fileprivate extension Notification {
    var interruptionType: InterruptionType? {
        guard let typeValue = self.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber else {
            Log(.error, "Could not extract interruption type from notification \(self)")
            return nil
        }
        
        guard let type = AVAudioSession.InterruptionType(rawValue: typeValue.uintValue) else {
            Log(.error, "Could not convert interruption type to AVAudioSession.InterruptionType \(typeValue)")
            return nil
        }
        
        if type == .began {
            return .began
        }
        
        guard let optionsValue = self.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt else {
            Log(.error, "Could not extract interruption options from notification \(self)")
            return nil
        }
        
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        if options.contains(.shouldResume) {
            return .shouldResume
        }
        
        Log(.error, "Unsupported interruption type: \(type) with options: \(options)")
        return nil
    }
    
    var interruptionReason: AVAudioSession.InterruptionReason? {
#if os(tvOS)
        return nil
#else
        guard let typeValue = self.userInfo?[AVAudioSessionInterruptionReasonKey] as? NSNumber else {
            Log(.error, "Could not extract interruption reason from notification: \(self)")
            return nil
        }
        
        guard let type = AVAudioSession.InterruptionReason(rawValue: typeValue.uintValue) else {
            Log(.error, "Could not convert interruption reason value to AVAudioSession.InterruptionReason: \(typeValue)")
            return nil
        }
        
        return type
#endif
    }
    
    var interruptionOptions: AVAudioSession.InterruptionOptions? {
#if os(tvOS)
        return nil
#else
        guard let typeValue = self.userInfo?[AVAudioSessionInterruptionOptionKey] as? NSNumber else {
            Log(.error, "Could not extract interruption reason from notification: \(self)")
            return nil
        }
        
        return AVAudioSession.InterruptionOptions(rawValue: typeValue.uintValue)
#endif
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
        Log(.info, "Session activated, current route: \(AVAudioSession.shared.currentRoute)")
        PostHogSDK.shared.capture("Audio session activated", properties: [
            "current route" : String(describing: AVAudioSession.shared.currentRoute)
        ])
    }
    
    func deactivate() throws {
        try setActive(false)
    }
}
