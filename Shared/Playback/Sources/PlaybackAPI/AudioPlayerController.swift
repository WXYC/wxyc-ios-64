//
//  AudioPlayerController.swift
//  Playback
//
//  High-level audio player controller that handles system integration.
//  Works with any AudioPlayerProtocol implementation (MP3Streamer, RadioPlayer, etc.)
//
//  Created by Jake Bromberg on 11/30/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import AVFoundation
import Core
import Foundation
import MediaPlayer
import PlaybackCore
import Analytics
#if canImport(Intents)
import Intents
#endif
#if os(iOS)
import UIKit
#endif

// Platform-specific imports for default player
#if !os(watchOS)
import MP3StreamerModule
#endif
import RadioPlayerModule

/// High-level controller for audio playback.
/// Handles audio session, remote commands, notifications, analytics, and system integration.
/// Works with any AudioPlayerProtocol implementation.
@MainActor
@Observable
public final class AudioPlayerController {

    // MARK: - Singleton

    #if os(iOS) || os(tvOS)
    /// Shared singleton instance for iOS/tvOS using MP3Streamer
    public static let shared = AudioPlayerController(
        player: MP3Streamer(
            configuration: MP3StreamerConfiguration(url: RadioStation.WXYC.streamURL)
        ),
        audioSession: AVAudioSession.sharedInstance(),
        remoteCommandCenter: SystemRemoteCommandCenter(),
        notificationCenter: .default,
        analytics: StructuredPostHogAnalytics.shared
    )
    #elseif os(watchOS)
    /// Shared singleton instance for watchOS using RadioPlayer
    public static let shared = AudioPlayerController(
        player: RadioPlayer(),
        notificationCenter: .default,
        analytics: StructuredPostHogAnalytics.shared
    )
    #else
    /// Shared singleton instance for macOS using MP3Streamer
    public static let shared = AudioPlayerController(
        player: MP3Streamer(
            configuration: MP3StreamerConfiguration(url: RadioStation.WXYC.streamURL)
        ),
        notificationCenter: .default,
        analytics: StructuredPostHogAnalytics.shared
    )
    #endif
    
    // MARK: - Public Properties
    
    /// Whether audio is currently playing
    public var isPlaying: Bool {
        player.isPlaying
    }

    /// Whether playback is loading (play initiated but not yet playing, or buffering)
    /// Excludes error and stopped states to prevent infinite loading
    public var isLoading: Bool {
        playbackIntended && (!isPlaying || player.state == .loading) && !player.state.isError
    }

    // MARK: - Dependencies
    // These are nonisolated(unsafe) to allow cleanup in deinit

    @ObservationIgnored private nonisolated(unsafe) var player: AudioPlayerProtocol
    @ObservationIgnored private nonisolated(unsafe) var notificationCenter: NotificationCenter
    @ObservationIgnored private nonisolated(unsafe) var analytics: AnalyticsService

    #if os(iOS) || os(tvOS)
    @ObservationIgnored private nonisolated(unsafe) var audioSession: AudioSessionProtocol?
    @ObservationIgnored private nonisolated(unsafe) var remoteCommandCenter: RemoteCommandCenterProtocol?
    #endif

    // MARK: - State

    private var wasPlayingBeforeInterruption = false
    /// Tracks if we intend to be playing (survives transient state changes)
    private var playbackIntended = false
    /// Tracks whether the audio session has been activated (to avoid deactivating when never activated)
    private var audioSessionActivated = false
    /// Tracks when playback started for analytics duration reporting
    private var playbackStartTime: Date?
    private var stallStartTime: Date?
    @ObservationIgnored private nonisolated(unsafe) var notificationObservers: [Any] = []
    @ObservationIgnored private nonisolated(unsafe) var commandTargets: [Any] = []

    @ObservationIgnored private var eventTask: Task<Void, Never>?

    // Exponential backoff for reconnection
    @ObservationIgnored internal var backoffTimer: ExponentialBackoff
    private var reconnectTask: Task<Void, Never>?
    
    // CPU Session Aggregation
    @ObservationIgnored private var cpuAggregator: CPUSessionAggregator?
    private var isForegrounded = true
    
    // MARK: - Initialization

    #if os(iOS) || os(tvOS)
    /// Creates a controller with injected dependencies (iOS/tvOS)
    /// - Parameters:
    ///   - player: The audio player implementation to use
    ///   - audioSession: Audio session for managing system audio behavior
    ///   - remoteCommandCenter: Remote command center for Lock Screen/Control Center integration
    ///   - notificationCenter: Notification center for system notifications
    ///   - analytics: Analytics service for playback events
    ///   - backoffTimer: Exponential backoff timer for reconnection attempts
    public init(
        player: AudioPlayerProtocol,
        audioSession: AudioSessionProtocol?,
        remoteCommandCenter: RemoteCommandCenterProtocol?,
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        backoffTimer: ExponentialBackoff = .default
    ) {
        self.player = player
        self.audioSession = audioSession
        self.remoteCommandCenter = remoteCommandCenter
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer

        // NOTE: We intentionally do NOT call configureAudioSessionIfNeeded() here.
        // Setting the audio session category to .playback during init interrupts
        // other apps' audio. Configuration is deferred until play() is called.
        setUpRemoteCommandCenter()
        setUpNotifications()
        setUpPlayerObservation()
        setUpCPUAggregator()
    }
    #else
    /// Creates a controller with injected dependencies (macOS/watchOS)
    /// - Parameters:
    ///   - player: The audio player implementation to use
    ///   - notificationCenter: Notification center for system notifications
    ///   - analytics: Analytics service for playback events
    ///   - backoffTimer: Exponential backoff timer for reconnection attempts
    public init(
        player: AudioPlayerProtocol,
        notificationCenter: NotificationCenter = .default,
        analytics: AnalyticsService = StructuredPostHogAnalytics.shared,
        backoffTimer: ExponentialBackoff = .default
    ) {
        self.player = player
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        self.backoffTimer = backoffTimer

        setUpPlayerObservation()
        setUpCPUAggregator()
    }
    #endif

    @MainActor
    deinit {
        eventTask?.cancel()
        reconnectTask?.cancel()
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer)
        }
        #if os(iOS) || os(tvOS)
        removeRemoteCommandTargets()
        #endif
    }

    // MARK: - Public Methods

    /// Toggle playback state
    public func toggle() {
        if isPlaying {
            analytics.capture(PlaybackStoppedEvent(duration: playbackDuration))
            stop()
        } else {
            play()
        }
    }

    /// Start playback
    public func play(reason: String = "play") {
        let context: PlaybackContext = isForegrounded ? .foreground : .background
        cpuAggregator?.startSession(context: context)

        playbackIntended = true
        playbackStartTime = playbackStartTime ?? Date()
        #if os(iOS) || os(tvOS)
        activateAudioSession()
        #endif

        // Always play fresh for live streaming (don't resume paused state)
        player.play()
        analytics.capture(PlaybackStartedEvent(reason: reason))
        donatePlayIntent()
    }
    
    /// Calculate how long playback has been active
    private var playbackDuration: TimeInterval {
        guard let startTime = playbackStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    /// Stop playback and disconnect from stream
    /// Note: Analytics should be captured at call sites BEFORE calling this method
    public func stop(reason _: String? = nil) {
        cpuAggregator?.endSession(reason: .userStopped)

        reconnectTask?.cancel()
        reconnectTask = nil
        backoffTimer.reset()

        playbackIntended = false
        player.stop()
        playbackStartTime = nil
        #if os(iOS) || os(tvOS)
        deactivateAudioSession()
        #endif
    }

    // MARK: - CPU Session Aggregation

    private func setUpCPUAggregator() {
        #if !os(watchOS)
        self.cpuAggregator = CPUSessionAggregator(
            analytics: analytics,
            playerTypeProvider: { [weak self] in
                // Determine player type from the actual player instance
                guard let self else { return .mp3Streamer }
                if self.player is RadioPlayer {
                    return .radioPlayer
                }
                return .mp3Streamer
            }
        )
        #endif
    }

    // MARK: - Audio Session (iOS/tvOS only)

    #if os(iOS) || os(tvOS)
    /// Audio session category is configured lazily on first play() to avoid
    /// interrupting other apps' audio during app launch.
    private var audioSessionConfigured = false
    
    private func configureAudioSessionIfNeeded() {
        guard !audioSessionConfigured, let session = audioSession else { return }
        audioSessionConfigured = true
        do {
            try session.setCategory(.playback, mode: .default, options: [])
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func activateAudioSession() {
        guard let session = audioSession else { return }
        // Configure the audio session category if not already done
        configureAudioSessionIfNeeded()
        do {
            try session.setActive(true, options: [])
            audioSessionActivated = true
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }

    private func deactivateAudioSession() {
        // Only deactivate if we previously activated - AVAudioSession has no isActive property
        guard audioSessionActivated, let session = audioSession else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActivated = false
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
    }
    #endif

    // MARK: - Remote Command Center (iOS/tvOS only)

    #if os(iOS) || os(tvOS)
    private func setUpRemoteCommandCenter() {
        guard let commandCenter = remoteCommandCenter else { return }

        // Play command
        commandCenter.playCommand.isEnabled = true
        let playTarget = commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.play()
            }
            return .success
        }
        commandTargets.append(playTarget)

        // Pause command
        commandCenter.pauseCommand.isEnabled = true
        let pauseTarget = commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.analytics.capture(PlaybackStoppedEvent(duration: self.playbackDuration))
                self.stop()
            }
            return .success
        }
        commandTargets.append(pauseTarget)

        // Toggle play/pause command
        commandCenter.togglePlayPauseCommand.isEnabled = true
        let toggleTarget = commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in
                self.toggle()
            }
            return .success
        }
        commandTargets.append(toggleTarget)

        // Disable unsupported commands for live streaming
        commandCenter.stopCommand.isEnabled = false
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        commandCenter.seekForwardCommand.isEnabled = false
        commandCenter.seekBackwardCommand.isEnabled = false
        commandCenter.changePlaybackPositionCommand.isEnabled = false
    }

    private func removeRemoteCommandTargets() {
        guard let commandCenter = remoteCommandCenter else { return }

        for target in commandTargets {
            commandCenter.playCommand.removeTarget(target)
            commandCenter.pauseCommand.removeTarget(target)
            commandCenter.togglePlayPauseCommand.removeTarget(target)
        }
        commandTargets.removeAll()
    }
    #endif

    // MARK: - Notifications (iOS/tvOS only)

    #if os(iOS) || os(tvOS)
    private func setUpNotifications() {
        // Handle audio interruptions
        let interruptionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleInterruption(typeValue: typeValue, optionsValue: optionsValue)
            }
        }
        notificationObservers.append(interruptionObserver)

        // Handle route changes
        let routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            let userInfo = notification.userInfo
            let reasonValue = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                self?.handleRouteChange(reasonValue: reasonValue)
            }
        }
        notificationObservers.append(routeChangeObserver)
    }
    #endif

    // MARK: - App Lifecycle (iOS only)
    // These methods should be called from SwiftUI's scenePhase handler
    // rather than using UIApplication notifications, to avoid race conditions
        
    #if os(iOS)
    /// Call this when the app enters the background (from SwiftUI scenePhase)
    /// Only deactivates the audio session if playback is NOT intended
    public func handleAppDidEnterBackground() {
        isForegrounded = false
        if isPlaying {
            cpuAggregator?.transitionContext(to: .background)
        }
        guard !playbackIntended else { return }
        deactivateAudioSession()
    }
            
    /// Call this when the app enters the foreground (from SwiftUI scenePhase)
    /// Reactivates the audio session if playback is intended
    public func handleAppWillEnterForeground() {
        isForegrounded = true
        if isPlaying {
            cpuAggregator?.transitionContext(to: .foreground)
        }
        if playbackIntended {
            activateAudioSession()
        }
    }
    #endif

    #if os(iOS) || os(tvOS)
    private func handleInterruption(typeValue: UInt?, optionsValue: UInt?) {
        guard let typeValue = typeValue,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                analytics.capture(PlaybackStoppedEvent(reason: "interruption began", duration: playbackDuration))
                stop()
            }
            
        case .ended:
            guard let optionsValue = optionsValue else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)

            if options.contains(.shouldResume) && wasPlayingBeforeInterruption {
                play()
            }
            wasPlayingBeforeInterruption = false
            
        @unknown default:
            break
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard let reasonValue = reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged - stop playback per Apple HIG
            if isPlaying {
                analytics.capture(PlaybackStoppedEvent(reason: "route disconnected", duration: playbackDuration))
                stop()
            }

        default:
            // AudioEnginePlayer handles restarting the engine on configuration changes
            break
        }
    }
    #endif

    // MARK: - Intent Donation

    /// Donates an INPlayMediaIntent to Siri so WXYC appears in Lock Screen suggestions.
    /// iOS learns from these donations to surface the app based on user listening patterns.
    private func donatePlayIntent() {
        #if canImport(Intents) && !os(macOS)
        let mediaItem = INMediaItem(
            identifier: RadioStation.WXYC.name,
            title: "WXYC 89.3 FM",
            type: .radioStation,
            artwork: nil
        )

        let intent = INPlayMediaIntent(
            mediaItems: [mediaItem],
            mediaContainer: nil,
            playShuffled: nil,
            resumePlayback: true,
            playbackQueueLocation: .now,
            playbackSpeed: nil
        )

        let interaction = INInteraction(intent: intent, response: nil)
        Task { try? await interaction.donate() }
        #endif
    }
}

// MARK: - Convenience for views

extension AudioPlayerController {
    /// Stream of audio buffers for visualization
    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        player.audioBufferStream
    }

    /// Install the render tap for audio visualization.
    /// The tap runs at ~60Hz and consumes CPU, so only install when actively displaying visualizations.
    public func installRenderTap() {
        player.installRenderTap()
    }

    /// Remove the render tap when visualization is no longer needed.
    public func removeRenderTap() {
        player.removeRenderTap()
    }

    private func setUpPlayerObservation() {
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in player.eventStream {
                switch event {
                case .stall:
                    handleStall()
                case .recovery:
                    handleRecovery()
                case .error(let error):
                    // Capture analytics for the error
                    let playerType: PlayerControllerType = self.player is RadioPlayer ? .radioPlayer : .mp3Streamer
                    self.analytics.capture(StreamErrorEvent(
                        playerType: playerType,
                        errorType: self.classifyError(error),
                        errorDescription: error.localizedDescription,
                        reconnectAttempts: Int(self.backoffTimer.numberOfAttempts),
                        sessionDuration: self.playbackDuration,
                        stallDuration: self.stallStartTime.map { Date().timeIntervalSince($0) },
                        recoveryMethod: .automaticReconnect
                    ))
                    self.cpuAggregator?.endSession(reason: .error)
                    print("AudioPlayerController received error: \(error)")
                }
            }
        }
    }

    private func handleStall() {
        stallStartTime = Date()
        analytics.capture(PlaybackStoppedEvent(reason: "stalled", duration: playbackDuration))

        // Attempt reconnection with exponential backoff
        attemptReconnectWithExponentialBackoff()
    }

    private func handleRecovery() {
        captureRecoveryIfNeeded()
    }

    private func attemptReconnectWithExponentialBackoff() {
        guard let waitTime = self.backoffTimer.nextWaitTime() else {
            // Backoff exhausted - capture error analytics
            let playerType: PlayerControllerType = player is RadioPlayer ? .radioPlayer : .mp3Streamer
            let stallDuration = stallStartTime.map { Date().timeIntervalSince($0) }
            analytics.capture(StreamErrorEvent(
                playerType: playerType,
                errorType: .backoffExhausted,
                errorDescription: "Maximum reconnection attempts (\(backoffTimer.maximumAttempts)) exhausted",
                reconnectAttempts: Int(backoffTimer.numberOfAttempts),
                sessionDuration: playbackDuration,
                stallDuration: stallDuration,
                recoveryMethod: .retryWithBackoff
            ))
            cpuAggregator?.endSession(reason: .error)
            print("Backoff exhausted after \(self.backoffTimer.numberOfAttempts) attempts, giving up reconnection.")
            self.backoffTimer.reset()
            return
        }

        reconnectTask = Task { [weak self] in
            guard let self else { return }

            if self.player.isPlaying {
                self.captureRecoveryIfNeeded()
                self.backoffTimer.reset()
                return
            }

            do {
                self.player.play()
                try await Task.sleep(for: .seconds(waitTime))

                guard !Task.isCancelled else { return }
                if !player.isPlaying {
                    attemptReconnectWithExponentialBackoff()
                } else {
                    captureRecoveryIfNeeded()
                    self.backoffTimer.reset()
                }
            } catch {
                self.backoffTimer.reset()
            }
        }
    }

    private func captureRecoveryIfNeeded() {
        guard let stallStart = self.stallStartTime else { return }
        let playerType: PlayerControllerType = player is RadioPlayer ? .radioPlayer : .mp3Streamer
        analytics.capture(StallRecoveryEvent(
            playerType: playerType,
            successful: true,
            attempts: Int(self.backoffTimer.numberOfAttempts),
            stallDuration: Date().timeIntervalSince(stallStart),
            reason: .bufferUnderrun,
            recoveryMethod: backoffTimer.numberOfAttempts > 0 ? .retryWithBackoff : .automaticReconnect
        ))
        self.stallStartTime = nil
    }

    /// Classifies an error into a StreamErrorType for analytics
    private func classifyError(_ error: Error) -> StreamErrorType {
        let nsError = error as NSError

        // Check for URL/network errors
        if nsError.domain == NSURLErrorDomain {
            return .networkError
        }

        // Check for AVFoundation errors
        if nsError.domain == AVFoundationErrorDomain {
            switch nsError.code {
            case AVError.decoderNotFound.rawValue,
                 AVError.decoderTemporarilyUnavailable.rawValue,
                 AVError.failedToParse.rawValue:
                return .decodingError
            default:
                return .playerError
            }
        }

        // Check for CoreMedia errors (often decoding-related)
        if nsError.domain == "CoreMediaErrorDomain" {
            return .decodingError
        }

        return .unknown
    }
}

// MARK: - PlaybackController Conformance

extension AudioPlayerController: PlaybackController {

    public var state: PlaybackState {
        // If there's a stall in progress, return stalled
        if stallStartTime != nil {
            return .stalled
        }

        // Convert PlayerState to PlaybackState
        // PlayerState doesn't include .interrupted (controller-level concern)
        return player.state.asPlaybackState
    }

    public func toggle(reason: String) throws {
        // AudioPlayerController's toggle doesn't take a reason,
        // but we match the protocol signature
        toggle()
    }

    // Explicit stop() to satisfy protocol (AudioPlayerController has stop(reason:))
    public func stop() {
        stop(reason: nil)
    }
}
