//
//  AudioPlayerController.swift
//  StreamingAudioPlayer
//
//  High-level audio player controller that handles system integration
//

import Foundation
import AVFoundation
import MediaPlayer
#if os(iOS)
import UIKit
#endif
import Core
import Caching
import WidgetKit
import PlaybackCore
import RadioPlayerModule
import AVAudioStreamerModule


// AudioPlayerController is not available on watchOS.
// Use RadioPlayerController from the Core module on watchOS instead.
#if !os(watchOS)

/// High-level controller for audio playback
/// Handles audio session, remote commands, and system notifications
@MainActor
@Observable
public final class AudioPlayerController {
    
    // MARK: - Singleton
    
    #if os(iOS) || os(tvOS)
    /// Shared singleton instance for app-wide usage (iOS/tvOS)
    public static let shared = AudioPlayerController(
        audioSession: AVAudioSession.sharedInstance(),
        remoteCommandCenter: SystemRemoteCommandCenter(),
        notificationCenter: .default,
        analytics: PostHogPlaybackAnalytics.shared
    )
    #else
    /// Shared singleton instance for app-wide usage (macOS)
    public static let shared = AudioPlayerController(
        notificationCenter: .default,
        analytics: PostHogPlaybackAnalytics.shared
    )
    #endif
    
    // MARK: - Player Factory
    
    /// Creates an audio player instance based on the controller type
    private static func createPlayer(for type: PlayerControllerType) -> AudioPlayerProtocol {
        switch type {
        case .radioPlayer:
            // RadioPlayer conforms to AudioPlayerProtocol directly
            return RadioPlayer()

        case .avAudioStreamer:
            // AVAudioStreamer conforms to AudioPlayerProtocol directly
            let config = AVAudioStreamerConfiguration(url: RadioStation.WXYC.streamURL)
            return AVAudioStreamer(configuration: config)
        }
    }
    
    // MARK: - Public Properties
    
    public var playerType: PlayerControllerType = .avAudioStreamer {
        didSet {
            replacePlayer(Self.createPlayer(for: playerType))
        }
    }
    
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
    @ObservationIgnored private nonisolated(unsafe) var analytics: PlaybackAnalytics
    
    #if os(iOS) || os(tvOS)
    @ObservationIgnored private nonisolated(unsafe) var audioSession: AudioSessionProtocol?
    @ObservationIgnored private nonisolated(unsafe) var remoteCommandCenter: RemoteCommandCenterProtocol?
    #endif
    
    // MARK: - State
    
    private var wasPlayingBeforeInterruption = false
    /// Tracks if we intend to be playing (survives transient state changes)
    private var playbackIntended = false
    /// Tracks when playback started for analytics duration reporting
    private var playbackStartTime: Date?
    private var stallStartTime: Date?
    @ObservationIgnored private nonisolated(unsafe) var notificationObservers: [Any] = []
    @ObservationIgnored private nonisolated(unsafe) var commandTargets: [Any] = []
    
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    #if os(iOS) || os(tvOS)
    /// Creates a controller with injected dependencies (iOS/tvOS)
    /// - Parameter player: Optional player to use. If nil, creates default player using AudioPlayerProtocol.create(for:)
    public init(
        player: AudioPlayerProtocol? = nil,
        audioSession: AudioSessionProtocol?,
        remoteCommandCenter: RemoteCommandCenterProtocol?,
        notificationCenter: NotificationCenter = .default,
        analytics: PlaybackAnalytics = PostHogPlaybackAnalytics.shared
    ) {
        self.player = player ?? Self.createPlayer(for: .avAudioStreamer)
        self.audioSession = audioSession
        self.remoteCommandCenter = remoteCommandCenter
        self.notificationCenter = notificationCenter
        self.analytics = analytics

        setUpAudioSession()
        setUpRemoteCommandCenter()
        setUpNotifications()
        setUpPlayerObservation()
    }
    #else
    /// Creates a controller with injected dependencies (macOS)
    /// - Parameter player: Optional player to use. If nil, creates default player using AudioPlayerProtocol.create(for:)
    public init(
        player: AudioPlayerProtocol? = nil,
        notificationCenter: NotificationCenter = .default,
        analytics: PlaybackAnalytics = PostHogPlaybackAnalytics.shared
    ) {
        self.player = player ?? Self.createPlayer(for: .avAudioStreamer)
        self.notificationCenter = notificationCenter
        self.analytics = analytics
    }
    #endif
    
    @MainActor
    deinit {
        eventTask?.cancel()
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer)
        }
        #if os(iOS) || os(tvOS)
        removeRemoteCommandTargets()
        #endif
    }
    
    // MARK: - Public Methods
    
    /// Replace the underlying audio player with a new instance
    /// The new player must be created with the same streamURL
    private func replacePlayer(_ newPlayer: AudioPlayerProtocol) {
        let wasPlaying = isPlaying
        
        // Stop current player
        if wasPlaying {
            player.stop()
        }
        
        // Replace player
        player = newPlayer
        setUpPlayerObservation()
        
        // Restore playback state if it was playing
        if wasPlaying {
            playbackIntended = true
            playbackStartTime = playbackStartTime ?? Date()
            #if os(iOS) || os(tvOS)
            activateAudioSession()
            #endif
            player.play()
        }
    }
    
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
        playbackIntended = true
        playbackStartTime = playbackStartTime ?? Date()
        #if os(iOS) || os(tvOS)
        activateAudioSession()
        #endif

        // Always play fresh for live streaming (don't resume paused state)
        player.play()
        analytics.capture(PlaybackStartedEvent(reason: reason))
        updateWidgetState()
    }
    
    /// Calculate how long playback has been active
    private var playbackDuration: TimeInterval {
        guard let startTime = playbackStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    /// Stop playback and disconnect from stream
    /// Note: Analytics should be captured at call sites BEFORE calling this method
    public func stop(reason: String? = nil) {
        playbackIntended = false
        player.stop()
        playbackStartTime = nil
        #if os(iOS) || os(tvOS)
        deactivateAudioSession()
        #endif
        updateWidgetState()
    }
    
    // MARK: - Audio Session (iOS/tvOS only)
    
    #if os(iOS) || os(tvOS)
    private func setUpAudioSession() {
        guard let session = audioSession else { return }
        do {
            try session.setCategory(.playback, mode: .default, options: [])
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func activateAudioSession() {
        guard let session = audioSession else { return }
        do {
            try session.setActive(true, options: [])
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }
    
    private func deactivateAudioSession() {
        guard let session = audioSession else { return }
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
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
        guard !playbackIntended else { return }
        deactivateAudioSession()
    }
    
    /// Call this when the app enters the foreground (from SwiftUI scenePhase)
    /// Reactivates the audio session if playback is intended
    public func handleAppWillEnterForeground() {
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
            // Headphones unplugged - stop playback
            if isPlaying {
                analytics.capture(PlaybackStoppedEvent(reason: "route disconnected", duration: playbackDuration))
                stop()
            }
            
        case .newDeviceAvailable:
            // New device connected - no action needed
            break
            
        default:
            break
        }
    }
    #endif
            
    private func updateWidgetState() {
        UserDefaults.wxyc.set(isPlaying, forKey: "isPlaying")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Convenience for views

extension AudioPlayerController {
    /// Stream of audio buffers for visualization
    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        player.audioBufferStream
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
                    // Log error but don't crash
                    print("AudioPlayerController received error: \(error)")
                }
            }
        }
    }
    
    private func handleStall() {
        stallStartTime = Date()
        analytics.capture(PlaybackStoppedEvent(reason: "stalled", duration: playbackDuration))
    }

    private func handleRecovery() {
        guard let stallStart = stallStartTime else { return }
        analytics.capture(StallRecoveryEvent(
            playerType: playerType,
            successful: true,
            attempts: 1,
            stallDuration: Date().timeIntervalSince(stallStart),
            reason: .bufferUnderrun,
            recoveryMethod: .automaticReconnect
        ))
        stallStartTime = nil
    }
}
    
extension AudioPlayerController: PlaybackController {
    
    public var state: PlaybackState {
        // If there's a stall in progress, return stalled
        if stallStartTime != nil {
            return .stalled
        }
    
        // Player now uses PlaybackState directly
        return player.state
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

#endif
