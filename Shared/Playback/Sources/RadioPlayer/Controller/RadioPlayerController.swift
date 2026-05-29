//
//  RadioPlayerController.swift
//  Playback
//
//  High-level controller for RadioPlayer with system integration.
//
//  Created by Jake Bromberg on 03/26/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer
import Logger
import SwiftUI
import Core
import PlaybackCore
import Analytics
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
            analytics: StructuredPostHogAnalytics.shared,
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
            analytics: StructuredPostHogAnalytics.shared
        )
    }
    #endif

    #if os(iOS) || os(tvOS)
    init(
        radioPlayer: any AudioPlayerProtocol = RadioPlayer(),
        audioSession: AudioSessionProtocol = AVAudioSession.sharedInstance(),
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        remoteCommandCenter: MPRemoteCommandCenter = .shared(),
        backoffTimer: ExponentialBackoff = .default
    ) {
        self.radioPlayer = radioPlayer
        self.audioSession = audioSession
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer

        setUpObservations(notificationCenter: notificationCenter, remoteCommandCenter: remoteCommandCenter)
        setUpPlayerStateObservation()
    }
    #else
    init(
        radioPlayer: any AudioPlayerProtocol = RadioPlayer(),
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        backoffTimer: ExponentialBackoff = .default
    ) {
        self.radioPlayer = radioPlayer
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer

        setUpObservations(notificationCenter: notificationCenter, remoteCommandCenter: nil)
        setUpPlayerStateObservation()
    }
    #endif

    @MainActor
    deinit {
        #if os(iOS) || os(tvOS)
        if let interruptionObservation { notificationCenter.removeObserver(interruptionObservation) }
        if let routeChangeObservation { notificationCenter.removeObserver(routeChangeObservation) }
        #endif
        if let stallObservation { notificationCenter.removeObserver(stallObservation) }
        #if os(iOS)
        if let backgroundObservation { notificationCenter.removeObserver(backgroundObservation) }
        if let foregroundObservation { notificationCenter.removeObserver(foregroundObservation) }
        #endif
        reconnectTask?.cancel()
    }

    private func setUpObservations(
        notificationCenter: NotificationCenter,
        remoteCommandCenter: MPRemoteCommandCenter?
    ) {
        #if os(iOS) || os(tvOS)
        interruptionObservation = notificationCenter.addMainActorObserver(
            for: InterruptionMessage.self
        ) { [weak self] message in
            self?.handleSessionInterrupted(message)
        }
        routeChangeObservation = notificationCenter.addMainActorObserver(
            for: RouteChangeMessage.self
        ) { [weak self] message in
            self?.handleRouteChanged(message)
        }
        #endif

        stallObservation = notificationCenter.addMainActorObserver(
            for: PlaybackStalledMessage.self
        ) { [weak self] _ in
            self?.handlePlaybackStalled()
        }

        #if os(iOS)
        backgroundObservation = notificationCenter.addMainActorObserver(
            for: AppDidEnterBackgroundMessage.self
        ) { [weak self] _ in
            self?.handleApplicationDidEnterBackground()
        }
        foregroundObservation = notificationCenter.addMainActorObserver(
            for: AppWillEnterForegroundMessage.self
        ) { [weak self] _ in
            self?.handleApplicationWillEnterForeground()
        }
        #endif

        if let remoteCommandCenter {
            remoteCommandCenter.playCommand.addTarget(handler: self.remotePlayCommand)
            remoteCommandCenter.pauseCommand.addTarget(handler: self.remotePauseOrStopCommand)
            remoteCommandCenter.stopCommand.addTarget(handler: self.remotePauseOrStopCommand)
            remoteCommandCenter.togglePlayPauseCommand.addTarget(handler: self.remoteTogglePlayPauseCommand(_:))
        }
    }

    /// Callback fired when player state observation has started. Used by tests for synchronization.
    var onObserversReady: (() -> Void)?

    private func setUpPlayerStateObservation() {
        // Observe radioPlayer state and derive controller state
        Task { [weak self] in
            guard let self else { return }

            // Signal that observer is ready before entering the loop
            self.onObserversReady?()

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
    
    public func toggle(reason: PlaybackReason) throws {
        if self.isPlaying {
            analytics.capture(PlaybackStoppedEvent(duration: playbackTimer.duration()))
            self.stop(reason: reason)
        } else {
            try self.play(reason: reason)
        }
    }

    public func play(reason: PlaybackReason) throws {
        self.state = .loading
        self.playbackTimer = Timer.start()
        self.playbackIntended = true
        self.wasPlayingBeforeRouteDisconnect = false

        #if os(iOS) || os(tvOS)
        do {
            try audioSession.setActive(true, options: [])
        } catch {
            self.state = .error(.audioSessionActivationFailed(error.localizedDescription))
            self.playbackIntended = false
            analytics.capture(PlaybackStoppedEvent(
                reason: "audio session activation failed",
                duration: 0
            ))
            Log(.error, category: .playback, "RadioPlayerController could not start playback: \(error)")
            return
        }
        #endif

        analytics.capture(PlaybackStartedEvent(reason: reason.rawValue))
        self.radioPlayer.play()
        // State transitions to .playing when radioPlayer.isPlaying becomes true
    }
    
    /// Stops playback without capturing analytics.
    /// Call sites should capture analytics BEFORE calling this method.
    /// - Parameter reason: Why playback was stopped (for analytics)
    public func stop(reason: PlaybackReason) {
        reconnectTask?.cancel()
        reconnectTask = nil
        backoffTimer.reset()
        self.playbackIntended = false
        if reason != .routeDisconnected {
            self.wasPlayingBeforeRouteDisconnect = false
        }
        self.radioPlayer.stop()
        self.state = .idle
    }
    
    public func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer> {
        // RadioPlayerController uses AVPlayer which doesn't provide raw audio buffers
        // Return empty stream that finishes immediately
        AsyncStream { $0.finish() }
    }
    
    /// No-op: AVPlayer-based RadioPlayerController doesn't support render tap
    public func installRenderTap() {
        // AVPlayer doesn't expose raw audio buffers
    }

    /// No-op: AVPlayer-based RadioPlayerController doesn't support render tap
    public func removeRenderTap() {
        // AVPlayer doesn't expose raw audio buffers
    }
    
    #if os(iOS)
    public func handleAppDidEnterBackground() {
        handleApplicationDidEnterBackground()
    }

    public func handleAppWillEnterForeground() {
        handleApplicationWillEnterForeground()
    }
    #endif

    // MARK: Private

    private let radioPlayer: any AudioPlayerProtocol
    private let notificationCenter: NotificationCenter
    #if os(iOS) || os(tvOS)
    private var interruptionObservation: (any NSObjectProtocol)?
    private var routeChangeObservation: (any NSObjectProtocol)?
    #endif
    private var stallObservation: (any NSObjectProtocol)?
    #if os(iOS)
    private var backgroundObservation: (any NSObjectProtocol)?
    private var foregroundObservation: (any NSObjectProtocol)?
    #endif
    
    #if os(iOS) || os(tvOS)
    private let audioSession: AudioSessionProtocol
    #endif
    
    private var playbackTimer = Timer.start()
    internal var backoffTimer: ExponentialBackoff
    private var reconnectTask: Task<Void, Never>?

    private let analytics: AnalyticsService
    private var stallStartTime: Date?
    private var wasPlayingBeforeInterruption = false
    private var wasPlayingBeforeRouteDisconnect = false
    private var playbackIntended = false
}

private extension RadioPlayerController {
    // MARK: AVPlayer handlers

    func handlePlaybackStalled() {
        Log(.error, category: .playback, "Playback stalled")

        self.state = .stalled
        self.stallStartTime = Date()

        analytics.capture(PlaybackStoppedEvent(reason: "stalled", duration: playbackTimer.duration()))
        self.radioPlayer.stop()
        self.attemptReconnectWithExponentialBackoff()
    }

#if os(iOS) || os(tvOS)
    func handleSessionInterrupted(_ message: InterruptionMessage) {
        Log(.info, category: .playback, "Session interrupted: type=\(message.type.rawValue)")

        switch message.type {
        case .began:
            // Per Apple's guidance: always stop on interruption began
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                analytics.capture(InterruptionEvent(type: .began))
                analytics.capture(PlaybackStoppedEvent(reason: PlaybackReason.interruptionBegan.rawValue, duration: playbackTimer.duration()))
                self.stop(reason: .interruptionBegan)
            }
            self.state = .interrupted

        case .ended:
            if message.options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                try? self.play(reason: .resumeAfterInterruption)
            }
            wasPlayingBeforeInterruption = false

        @unknown default:
            break
        }
    }

    func handleRouteChanged(_ message: RouteChangeMessage) {
        Log(.info, category: .playback, "Session route changed: reason=\(message.reason.rawValue)")

        switch message.reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - stop playback per Apple HIG
            wasPlayingBeforeRouteDisconnect = isPlaying
            if isPlaying {
                analytics.capture(PlaybackStoppedEvent(reason: PlaybackReason.routeDisconnected.rawValue, duration: playbackTimer.duration()))
                self.stop(reason: .routeDisconnected)
            }

        case .newDeviceAvailable:
            // Device reconnected (e.g., AirPod reinserted) - resume if we were playing before disconnect
            if wasPlayingBeforeRouteDisconnect {
                try? self.play(reason: .resumeAfterRouteReconnect)
            } else if playbackIntended && !radioPlayer.isPlaying {
                radioPlayer.play()
            }

        default:
            // For all other route changes, check if playback was intended but
            // the player stopped unexpectedly. Restart if needed.
            if playbackIntended && !radioPlayer.isPlaying {
                radioPlayer.play()
            }
        }
    }
#endif

    private func attemptReconnectWithExponentialBackoff() {
        guard let waitTime = self.backoffTimer.nextWaitTime() else {
            // Backoff exhausted - capture error analytics
            let stallDuration = stallStartTime.map { Date().timeIntervalSince($0) }
            analytics.capture(StreamErrorEvent(
                playerType: .radioPlayer,
                errorType: .backoffExhausted,
                errorDescription: "Maximum reconnection attempts (\(backoffTimer.maximumAttempts)) exhausted",
                reconnectAttempts: Int(backoffTimer.numberOfAttempts),
                sessionDuration: playbackTimer.duration(),
                stallDuration: stallDuration,
                recoveryMethod: .retryWithBackoff
            ))
            Log(.info, category: .playback, "Backoff exhausted after \(self.backoffTimer.numberOfAttempts) attempts, giving up reconnection.")
            self.state = .error(.maxReconnectAttemptsExceeded)
            self.backoffTimer.reset()
            return
        }
        Log(.info, category: .playback, "Attempting to reconnect with exponential backoff \(self.backoffTimer).")
        reconnectTask = Task {
            if self.radioPlayer.isPlaying {
                captureRecoveryIfNeeded()
                self.backoffTimer.reset()
                return
            }

            do {
                self.radioPlayer.play()
                try await Task.sleep(nanoseconds: waitTime.nanoseconds)

                guard !Task.isCancelled else { return }
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

#if os(iOS)
    func handleApplicationDidEnterBackground() {
        guard !self.radioPlayer.isPlaying else {
            return
        }

        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            analytics.capture(Analytics.ErrorEvent(error: error, context: "RadioPlayerController could not deactivate"))
            Log(.error, category: .playback, "RadioPlayerController could not deactivate: \(error)")
        }
    }

    func handleApplicationWillEnterForeground() {
        if self.radioPlayer.isPlaying {
            try? self.play(reason: .foregroundToggle)
        } else {
            analytics.capture(PlaybackStoppedEvent(duration: playbackTimer.duration()))
            self.stop(reason: .foregroundNotPlaying)
        }
    }
#endif

    func remotePlayCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        do {
            try self.play(reason: .remotePlayCommand)
            return .success
        } catch {
            return .commandFailed
        }
    }

    func remotePauseOrStopCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        analytics.capture(PlaybackStoppedEvent(duration: playbackTimer.duration()))
        self.stop(reason: .remotePauseCommand)

        return .success
    }

    func remoteTogglePlayPauseCommand(_: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        do {
            if self.radioPlayer.isPlaying {
                analytics.capture(PlaybackStoppedEvent(duration: playbackTimer.duration()))
                self.stop(reason: .remoteToggleCommand)
            } else {
                try self.play(reason: .remoteToggleCommand)
            }

            return .success
        } catch {
            return .commandFailed
        }
    }
}
