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
import SwiftUI
import Core
import PlaybackCore
#if os(iOS)
import UIKit
#endif

@MainActor
@Observable
public final class RadioPlayerController: PlaybackController {
    #if os(iOS) || os(tvOS)
    public static let shared = RadioPlayerController(
        audioSession: AVAudioSession.sharedInstance(),
        remoteCommandCenter: .shared()
    )
    #else
    public static let shared = RadioPlayerController()
    #endif

    // MARK: - PlaybackController Protocol

    private let streamURL = RadioStation.WXYC.streamURL
    
    /// The current playback state
    public private(set) var state: PlaybackState = .idle

    public var isPlaying: Bool {
        self.radioPlayer.isPlaying
    }

    public var isLoading: Bool {
        // RadioPlayerController doesn't track loading state separately
        false
    }

    #if os(iOS) || os(tvOS)
    public convenience init(
        audioSession: AudioSessionProtocol = AVAudioSession.sharedInstance(),
        notificationCenter: NotificationCenter = .default,
        remoteCommandCenter: MPRemoteCommandCenter = .shared()
    ) {
        self.init(
            radioPlayer: RadioPlayer(),
            audioSession: audioSession,
            notificationCenter: notificationCenter,
            analytics: PostHogPlaybackAnalytics.shared,
            remoteCommandCenter: remoteCommandCenter
        )
    }
    #else
    public convenience init(
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            radioPlayer: RadioPlayer(),
            notificationCenter: notificationCenter,
            analytics: PostHogPlaybackAnalytics.shared
        )
    }
    #endif

    #if os(iOS) || os(tvOS)
    init(
        radioPlayer: any AudioPlayerProtocol = RadioPlayer(),
        audioSession: AudioSessionProtocol = AVAudioSession.sharedInstance(),
        notificationCenter: NotificationCenter = .default,
        analytics: PlaybackAnalytics = PostHogPlaybackAnalytics.shared,
        remoteCommandCenter: MPRemoteCommandCenter = .shared(),
        backoffTimer: ExponentialBackoff = .default
    ) {
        self.radioPlayer = radioPlayer
        self.audioSession = audioSession
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer

        self.inputObservations = []
        setUpObservations(notificationCenter: notificationCenter, remoteCommandCenter: remoteCommandCenter)
        setUpPlayerStateObservation()
    }
    #else
    init(
        radioPlayer: any AudioPlayerProtocol = RadioPlayer(),
        notificationCenter: NotificationCenter = .default,
        analytics: PlaybackAnalytics = PostHogPlaybackAnalytics.shared,
        backoffTimer: ExponentialBackoff = .default
    ) {
        self.radioPlayer = radioPlayer
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer

        self.inputObservations = []
        setUpObservations(notificationCenter: notificationCenter, remoteCommandCenter: nil)
        setUpPlayerStateObservation()
    }
    #endif

    private func setUpObservations(
        notificationCenter: NotificationCenter,
        remoteCommandCenter: MPRemoteCommandCenter?
    ) {
        func notificationObserver(
            for name: Notification.Name,
            sink: @escaping @Sendable (Notification) -> ()
        ) -> Any {
            notificationCenter.addObserver(forName: name, object: nil, queue: nil, using: sink)
        }

        var observations: [Any] = []

#if os(iOS)
        observations += [
            notificationObserver(for: UIApplication.didEnterBackgroundNotification, sink: self.applicationDidEnterBackground),
            notificationObserver(for: UIApplication.willEnterForegroundNotification, sink: self.applicationWillEnterForeground),
        ]
#endif

#if os(iOS) || os(tvOS)
        observations += [
            notificationObserver(for: AVAudioSession.interruptionNotification, sink: self.sessionInterrupted),
            notificationObserver(for: AVAudioSession.routeChangeNotification, sink: self.routeChanged),
        ]
#endif

        observations += [
            notificationObserver(for: .AVPlayerItemPlaybackStalled, sink: self.playbackStalled),
        ]

        // Set up remote command handlers if a command center was provided
        if let remoteCommandCenter {
            func remoteCommandObserver(
                for command: KeyPath<MPRemoteCommandCenter, MPRemoteCommand>,
                handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
            ) -> Any {
                remoteCommandCenter[keyPath: command].addTarget(handler: handler)
            }

            observations += [
                remoteCommandObserver(for: \.playCommand, handler: self.remotePlayCommand),
                remoteCommandObserver(for: \.pauseCommand, handler: self.remotePauseOrStopCommand),
                remoteCommandObserver(for: \.stopCommand, handler: self.remotePauseOrStopCommand),
                remoteCommandObserver(for: \.togglePlayPauseCommand, handler: self.remoteTogglePlayPauseCommand(_:)),
            ]
        }

        self.inputObservations = observations
    }

    private func setUpPlayerStateObservation() {
        // Observe radioPlayer state and derive controller state
        Task { [weak self] in
            guard let self else { return }
            for await playerState in self.radioPlayer.stateStream {
                // Don't overwrite controller-specific states like .interrupted
                guard self.state != .interrupted else { continue }

                // Map PlayerState to PlaybackState
                // PlayerState doesn't include .interrupted (controller-level concern)
                self.state = playerState.asPlaybackState
            }
        }
    }

    // MARK: Public methods
    
    public func toggle(reason: String) throws {
        if self.isPlaying {
            analytics.capture(PlaybackStoppedEvent(duration: playbackTimer.duration()))
            self.stop()
        } else {
            try self.play(reason: reason)
        }
    }

    public func play(reason: String) throws {
        self.state = .loading
        self.playbackTimer = Timer.start()
    
        #if os(iOS) || os(tvOS)
        do {
            try audioSession.setActive(true, options: [])
        } catch {
            self.state = .error(.audioSessionActivationFailed(error.localizedDescription))
            analytics.capture(PlaybackStoppedEvent(
                reason: "audio session activation failed",
                duration: 0
            ))
            Log(.error, "RadioPlayerController could not start playback: \(error)")
            return
        }
        #endif

        analytics.capture(PlaybackStartedEvent(reason: reason))
        self.radioPlayer.play()
        // State transitions to .playing when radioPlayer.isPlaying becomes true
    }

    /// Stops playback without capturing analytics.
    /// Call sites should capture analytics BEFORE calling this method.
    public func stop() {
        self.radioPlayer.stop()
        self.state = .idle
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

    private let radioPlayer: any AudioPlayerProtocol
    private let notificationCenter: NotificationCenter
    private var inputObservations: [Any] = []

    #if os(iOS) || os(tvOS)
    private let audioSession: AudioSessionProtocol
    #endif

    private var playbackTimer = Timer.start()
    internal var backoffTimer: ExponentialBackoff
    
    private let analytics: PlaybackAnalytics
    private var stallStartTime: Date?
    private var wasPlayingBeforeInterruption = false
}

private extension RadioPlayerController {
    // MARK: AVPlayer handlers
    
    nonisolated func playbackStalled(_ notification: Notification) {
        Log(.error, "Playback stalled: \(notification)")

        Task { @MainActor in
            self.state = .stalled
            self.stallStartTime = Date()

            analytics.capture(PlaybackStoppedEvent(reason: "stalled", duration: playbackTimer.duration()))
            self.radioPlayer.stop()
            self.attemptReconnectWithExponentialBackoff()
        }
    }
    
    nonisolated func sessionInterrupted(notification: Notification) {
#if os(iOS) || os(tvOS)
        Log(.info, "Session interrupted: \(notification)")

        let userInfo = notification.userInfo
        let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
        let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt

        Task { @MainActor in
            guard let typeValue,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            switch type {
            case .began:
                // Per Apple's guidance: always stop on interruption began
                wasPlayingBeforeInterruption = isPlaying
                if isPlaying {
                    analytics.capture(InterruptionEvent(type: .began))
                    // Use specific reason strings matching original pattern
                    analytics.capture(PlaybackStoppedEvent(reason: "interruption began", duration: playbackTimer.duration()))
                    self.stop()
                }
                self.state = .interrupted

            case .ended:
                // Check shouldResume option to decide whether to resume
                guard let optionsValue else { return }
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

                if options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                    try self.play(reason: "Resume after interruption ended")
                }
                wasPlayingBeforeInterruption = false

            @unknown default:
                break
            }
        }
#endif
    }
    
    nonisolated func routeChanged(_ notification: Notification) {
#if os(iOS) || os(tvOS)
        Log(.info, "Session route changed: \(notification)")
#endif
    }

    private func attemptReconnectWithExponentialBackoff() {
        guard let waitTime = self.backoffTimer.nextWaitTime() else {
            Log(.info, "Backoff exhausted after \(self.backoffTimer.numberOfAttempts) attempts, giving up reconnection.")
            self.backoffTimer.reset()
            return
        }
        Log(.info, "Attempting to reconnect with exponential backoff \(self.backoffTimer).")
        Task {
            if self.radioPlayer.isPlaying {
                captureRecoveryIfNeeded()
                self.backoffTimer.reset()
                return
            }

            do {
                self.radioPlayer.play()
                try await Task.sleep(nanoseconds: waitTime.nanoseconds)

                if !radioPlayer.isPlaying {
                    attemptReconnectWithExponentialBackoff()
                } else {
                    captureRecoveryIfNeeded()
                    self.backoffTimer.reset()
                }
            } catch {
                self.backoffTimer.reset()
                return
            }
        }
    }

    private func captureRecoveryIfNeeded() {
        guard let stallStart = self.stallStartTime else { return }
        analytics.capture(StallRecoveryEvent(
            playerType: .radioPlayer,
            successful: true,
            attempts: Int(self.backoffTimer.numberOfAttempts),
            stallDuration: Date().timeIntervalSince(stallStart),
            reason: .bufferUnderrun,
            recoveryMethod: .retryWithBackoff
        ))
        self.stallStartTime = nil
    }

    // MARK: External playback command handlers
    
    nonisolated func applicationDidEnterBackground(_: Notification) {
#if os(iOS) || os(tvOS)
        Task { @MainActor in
            guard !self.radioPlayer.isPlaying else {
                return
            }

            do {
                try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                analytics.capture(ErrorEvent(error: error, context: "RadioPlayerController could not deactivate"))
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
                analytics.capture(PlaybackStoppedEvent(duration: playbackTimer.duration()))
                self.stop()
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
        analytics.capture(PlaybackStoppedEvent(duration: playbackTimer.duration()))
        self.stop()

        return .success
    }
    
    func remoteTogglePlayPauseCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        do {
            if self.radioPlayer.isPlaying {
                analytics.capture(PlaybackStoppedEvent(duration: playbackTimer.duration()))
                self.stop()
            } else {
                try self.play(reason: "remote toggle play/pause")
            }

            return .success
        } catch {
            return .commandFailed
        }
    }
}

// MARK: - AVAudioSession Convenience

#if os(watchOS)
extension AVAudioSession {
    func activate() async throws -> Bool {
        let activated = try await AVAudioSession.sharedInstance().activate(options: [])
        Log(.info, "Session activated, current route: \(AVAudioSession.sharedInstance().currentRoute)")
        return activated
    }
}
#endif
