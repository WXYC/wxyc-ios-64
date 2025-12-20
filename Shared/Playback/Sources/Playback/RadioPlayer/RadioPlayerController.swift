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
import PostHog
import SwiftUI
import Core
#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
public final class RadioPlayerController: PlaybackController {
    public static let shared = RadioPlayerController()
    
    // MARK: - PlaybackController Protocol
    
    private let streamURL = RadioStation.WXYC.streamURL
    
    public var isPlaying: Bool {
        self.radioPlayer.isPlaying
    }
    
    public var isLoading: Bool {
        // RadioPlayerController doesn't track loading state separately
        false
    }
    
    public convenience init(
        notificationCenter: NotificationCenter = .default,
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.init(
            radioPlayer: RadioPlayer(),
            notificationCenter: .default,
            metricsReporter: PostHogSDK.shared,
            remoteCommandCenter: .shared()
        )
    }
    

    init(
        radioPlayer: RadioPlayer = RadioPlayer(),
        notificationCenter: NotificationCenter = .default,
        metricsReporter: PlaybackMetricsReporter = PostHogSDK.shared,
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        func notificationObserver(
            for name: Notification.Name,
            sink: @escaping @Sendable (Notification) -> ()
        ) -> Any {
            notificationCenter.addObserver(forName: name, object: nil, queue: nil, using: sink)
        }
        
        func remoteCommandObserver(
            for command: KeyPath<MPRemoteCommandCenter, MPRemoteCommand>,
            handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
        ) -> Any {
            remoteCommandCenter[keyPath: command].addTarget(handler: handler)
        }
        
        
        self.radioPlayer = radioPlayer
        self.metricsReporter = metricsReporter

        var observations: [Any] = []

#if os(iOS)
        observations += [
            notificationObserver(for: UIApplication.didEnterBackgroundNotification, sink: self.applicationDidEnterBackground),
            notificationObserver(for: UIApplication.willEnterForegroundNotification, sink: self.applicationWillEnterForeground),
        ]
#endif

#if !os(macOS)
        observations += [
            notificationObserver(for: AVAudioSession.interruptionNotification, sink: self.sessionInterrupted),
            notificationObserver(for: AVAudioSession.routeChangeNotification, sink: self.routeChanged),
        ]
#endif

        observations += [
            notificationObserver(for: .AVPlayerItemPlaybackStalled, sink: self.playbackStalled),

            remoteCommandObserver(for: \.playCommand, handler: self.remotePlayCommand),
            remoteCommandObserver(for: \.pauseCommand, handler: self.remotePauseOrStopCommand),
            remoteCommandObserver(for: \.stopCommand, handler: self.remotePauseOrStopCommand),
            remoteCommandObserver(for: \.togglePlayPauseCommand, handler: self.remoteTogglePlayPauseCommand(_:)),
        ]

        self.inputObservations = observations
    }
    
    // MARK: Public methods
    
    public func toggle(reason: String) throws {
        if self.isPlaying {
            PostHogSDK.shared.pause(duration: playbackTimer.duration())
            self.pause()
        } else {
            try self.play(reason: reason)
        }
    }
    
    public func play(reason: String) throws {
        Task {
            do {
                self.playbackTimer = Timer.start()

#if !os(macOS)
                let activated = try await AVAudioSession.sharedInstance().activate()
#else
                let activated = true
#endif

                if activated {
                    PostHogSDK.shared.play(reason: reason)
                    self.radioPlayer.play()
                } else {
                    let failedToActivateReason = "AVAudioSession.sharedInstance().activate() returned false, but no error was thrown. Original reason: \(reason)"
                    PostHogSDK.shared.play(reason: failedToActivateReason)
                }
            } catch {
                PostHogSDK.shared.capture(
                    error: error,
                    context: "RadioPlayerController could not start playback",
                    additionalData: ["reason" : reason]
                )

                Log(.error, "RadioPlayerController could not start playback: \(error)")
            }
        }
    }
    
    public func pause() {
        self.radioPlayer.pause()
    }
    
    public func stop() {
        // RadioPlayerController treats stop as pause for live streams
        self.pause()
    }
    
    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        // RadioPlayerController uses AVPlayer which doesn't provide raw audio buffers
        // Return empty stream that finishes immediately
        AsyncStream { continuation in
            continuation.finish()
        }
    }
    
    #if os(iOS)
    public func handleAppDidEnterBackground() {
        applicationDidEnterBackground(Notification(name: UIApplication.didEnterBackgroundNotification))
    }
    
    public func handleAppWillEnterForeground() {
        applicationWillEnterForeground(Notification(name: UIApplication.willEnterForegroundNotification))
    }
    #endif
    
    // MARK: Private
    
    private let radioPlayer: RadioPlayer
    private var inputObservations: [Any] = []
    
    private var playbackTimer = Timer.start()
    private var backoffTimer = ExponentialBackoff(initialWaitTime: 0.5, maximumWaitTime: 10.0)
    
    private let metricsReporter: PlaybackMetricsReporter
    private var stallStartTime: Date?
}

private extension RadioPlayerController {
    // MARK: AVPlayer handlers
    
    nonisolated func playbackStalled(_ notification: Notification) {
        Log(.error, "Playback stalled: \(notification)")
        
        Task { @MainActor in
            let event = StallEvent(
                playerType: .radioPlayer,
                timestamp: Date(),
                playbackDuration: playbackTimer.duration(),
                reason: .bufferUnderrun
            )
            metricsReporter.reportStall(event)
            self.stallStartTime = Date()
            
            PostHogSDK.shared.pause(duration: playbackTimer.duration(), reason: "playback stalled")
            self.radioPlayer.pause()
            self.attemptReconnectWithExponentialBackoff()
        }
    }
    
    nonisolated func sessionInterrupted(notification: Notification) {
#if !os(macOS)
        Log(.info, "Session interrupted: \(notification)")
        guard let interruptionType = notification.interruptionType else {
            return
        }

        let interruptionReason = notification.interruptionReason
        let iterruptionOptions = notification.interruptionOptions

        Task { @MainActor in

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
                try self.play(reason: "Resume AVAudioSession playback")
            }
        }
#endif
    }
    
    nonisolated func routeChanged(_: Notification) {
#if !os(macOS)
        // Use AVAudioSession.shared.currentRoute since the notification only provides the previous
        // audio output.
        Log(.info, "Session route changed: \(AVAudioSession.shared.currentRoute)")
#endif
    }
    
    private func attemptReconnectWithExponentialBackoff() {
        let waitTime = self.backoffTimer.nextWaitTime()
        Log(.info, "Attempting to reconnect with exponential backoff \(self.backoffTimer).")
        Task {
            if self.radioPlayer.isPlaying {
                if let stallStart = self.stallStartTime {
                    let event = RecoveryEvent(
                        playerType: .radioPlayer,
                        successful: true,
                        attemptCount: 1, 
                        stallDuration: Date().timeIntervalSince(stallStart),
                        recoveryMethod: .retryWithBackoff
                    )
                    metricsReporter.reportRecovery(event)
                    self.stallStartTime = nil
                }
                
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
    
    nonisolated func applicationDidEnterBackground(_: Notification) {
#if !os(macOS)
        Task { @MainActor in
            guard !self.radioPlayer.isPlaying else {
                return
            }

            do {
                try AVAudioSession.shared.deactivate()
            } catch let error as NSError {
                PostHogSDK.shared.capture(error: error, context: "RadioPlayerController could not deactivate")
                Log(.error, "RadioPlayerController could not deactivate: \(error)")
            }
        }
#endif
    }
    
    nonisolated func applicationWillEnterForeground(_: Notification) {
        Task { @MainActor in
            if self.radioPlayer.isPlaying {
                try self.play(reason: "foreground toggle")
            } else {
                PostHogSDK.shared.pause(duration: playbackTimer.duration())
                self.pause()
            }
        }
    }
    
    func remotePlayCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        do {
            try self.play(reason: "remotePlayCommand")
            return .success
        } catch {
            return .commandFailed
        }
    }
    
    func remotePauseOrStopCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        PostHogSDK.shared.pause(duration: playbackTimer.duration())
        self.pause()
        
        return .success
    }
    
    func remoteTogglePlayPauseCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        do {
            if self.radioPlayer.isPlaying {
                self.pause()
            } else {
                try self.play(reason: "remote toggle play/pause")
            }
            
            return .success
        } catch {
            return .commandFailed
        }
    }
}

fileprivate extension Notification {
    enum InterruptionType {
        case began
        case ended
        case shouldResume
    }
    
    var interruptionType: InterruptionType? {
#if os(macOS)
        return nil
#else
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
#endif
    }

#if !os(macOS)
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
#endif
}

#if !os(macOS)
extension AVAudioSession {
    static var shared: AVAudioSession {
        return AVAudioSession.sharedInstance()
    }

    func activate() async throws -> Bool {
#if os(watchOS)
        let activated = try await AVAudioSession.sharedInstance().activate(options: [])
#else
        let activated = true
        try setActive(true)
#endif

        Log(.info, "Session activated, current route: \(AVAudioSession.shared.currentRoute)")

        return activated
    }

    func deactivate() throws {
        try setActive(false)
    }
}
#endif
