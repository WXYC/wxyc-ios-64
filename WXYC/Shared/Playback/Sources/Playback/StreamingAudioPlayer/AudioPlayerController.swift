//
//  AudioPlayerController.swift
//  StreamingAudioPlayer
//
//  High-level audio player controller that handles system integration
//

import Foundation
import AVFoundation
import MediaPlayer
import Analytics
import PostHog
#if os(iOS)
import UIKit
#endif
import Core

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
        player: StreamingAudioPlayer(),
        audioSession: AVAudioSession.sharedInstance(),
        remoteCommandCenter: SystemRemoteCommandCenter(),
        notificationCenter: .default,
        analytics: PostHogSDK.shared
    )
    #else
    /// Shared singleton instance for app-wide usage (macOS)
    public static let shared = AudioPlayerController(
        player: StreamingAudioPlayer(),
        notificationCenter: .default,
        analytics: PostHogSDK.shared
    )
    #endif
    
    // MARK: - Player Factory
    
    /// Creates an audio player instance based on the controller type
    /// Note: Currently only StreamingAudioPlayer (audioPlayer type) is supported
    /// Other types would require adapters to conform to AudioPlayerProtocol
    @MainActor
    public static func createPlayer(for type: PlayerControllerType) -> AudioPlayerProtocol {
        switch type {
        case .audioPlayer, .radioPlayer, .avAudioStreamer, .miniMP3Streamer, .ffmpegAudio:
            // For now, all types use StreamingAudioPlayer since it's the only
            // implementation that conforms to AudioPlayerProtocol
            // TODO: Create adapters for other player types if needed
            return StreamingAudioPlayer()
        }
    }
    
    // MARK: - Public Properties
    
    /// Whether audio is currently playing
    public var isPlaying: Bool {
        player.isPlaying
    }
    
    /// Whether playback is loading (play initiated but not yet playing)
    public var isLoading: Bool {
        playbackIntended && player.state == .buffering
    }
    
    /// The current stream URL
    public var currentURL: URL? {
        player.currentURL
    }
    
    /// Default stream URL used by toggle() when no URL is currently set
    public var defaultStreamURL: URL?
    
    // MARK: - Dependencies
    // These are nonisolated(unsafe) to allow cleanup in deinit
    
    @ObservationIgnored private nonisolated(unsafe) var player: AudioPlayerProtocol
    @ObservationIgnored private nonisolated(unsafe) var notificationCenter: NotificationCenter
    @ObservationIgnored private nonisolated(unsafe) var analytics: AudioAnalyticsProtocol?
    
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
    @ObservationIgnored private nonisolated(unsafe) var notificationObservers: [Any] = []
    @ObservationIgnored private nonisolated(unsafe) var commandTargets: [Any] = []
    
    // MARK: - Initialization
    
    #if os(iOS) || os(tvOS)
    /// Creates a controller with injected dependencies (iOS/tvOS)
    public init(
        player: AudioPlayerProtocol,
        audioSession: AudioSessionProtocol?,
        remoteCommandCenter: RemoteCommandCenterProtocol?,
        notificationCenter: NotificationCenter = .default,
        analytics: AudioAnalyticsProtocol? = PostHogSDK.shared
    ) {
        self.player = player
        self.audioSession = audioSession
        self.remoteCommandCenter = remoteCommandCenter
        self.notificationCenter = notificationCenter
        self.analytics = analytics
        
        setupAudioSession()
        setupRemoteCommandCenter()
        setupNotifications()
    }
    #else
    /// Creates a controller with injected dependencies (macOS)
    public init(
        player: AudioPlayerProtocol,
        notificationCenter: NotificationCenter = .default,
        analytics: AudioAnalyticsProtocol? = PostHogSDK.shared
    ) {
        self.player = player
        self.notificationCenter = notificationCenter
        self.analytics = analytics
    }
    #endif
    
    @MainActor
    deinit {
        for observer in notificationObservers {
            notificationCenter.removeObserver(observer)
        }
        #if os(iOS) || os(tvOS)
        removeRemoteCommandTargets()
        #endif
    }
    
    // MARK: - Public Methods
    
    /// Replace the underlying audio player with a new instance
    /// Preserves current playback state and URL if playing
    @MainActor
    public func replacePlayer(_ newPlayer: AudioPlayerProtocol) {
        let wasPlaying = isPlaying
        let currentURL = player.currentURL
        
        // Stop current player
        if wasPlaying {
            player.stop()
        }
        
        // Transfer audio buffer handler if set
        if let handler = player.onAudioBuffer {
            newPlayer.onAudioBuffer = handler
        }
        
        // Transfer metadata handler if set
        if let handler = player.onMetadata {
            newPlayer.onMetadata = handler
        }
        
        // Replace player
        player = newPlayer
        
        // Restore playback state if it was playing
        if wasPlaying, let url = currentURL {
            playbackIntended = true
            playbackStartTime = playbackStartTime ?? Date()
            #if os(iOS) || os(tvOS)
            activateAudioSession()
            #endif
            player.play(url: url)
        }
    }
    
    /// Toggle playback state
    /// If no URL is currently set, uses `defaultStreamURL` if available
    public func toggle() {
        if isPlaying {
            pause()
        } else {
            // If no current URL, try defaultStreamURL
            if player.currentURL == nil, let defaultURL = defaultStreamURL {
                play(url: defaultURL)
            } else {
                play()
            }
        }
    }
    
    /// Start or resume playback
    public func play() {
        guard let url = player.currentURL else { return }
        playbackIntended = true
        playbackStartTime = playbackStartTime ?? Date()
        #if os(iOS) || os(tvOS)
        activateAudioSession()
        #endif
        
        if player.state == .paused {
            player.resume()
        } else {
            player.play(url: url)
        }
    }
    
    /// Start playback with a specific URL
    public func play(url: URL, reason: String = "play") {
        playbackIntended = true
        playbackStartTime = Date()
        #if os(iOS) || os(tvOS)
        activateAudioSession()
        #endif
        player.play(url: url)
        analytics?.play(source: #function, reason: reason)
    }
    
    /// Pause playback
    public func pause(reason: String? = nil) {
        playbackIntended = false
        let duration = playbackDuration
        player.pause()
        if let reason {
            analytics?.pause(source: #function, duration: duration, reason: reason)
        } else {
            analytics?.pause(source: #function, duration: duration)
        }
    }
    
    /// Calculate how long playback has been active
    private var playbackDuration: TimeInterval {
        guard let startTime = playbackStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }
    
    /// Stop playback completely
    public func stop(reason: String? = nil) {
        playbackIntended = false
        let duration = playbackDuration
        player.stop()
        if let reason {
            analytics?.pause(source: #function, duration: duration, reason: reason)
        } else {
            analytics?.pause(source: #function, duration: duration)
        }
        playbackStartTime = nil
        #if os(iOS) || os(tvOS)
        deactivateAudioSession()
        #endif
    }
    
    // MARK: - Audio Session (iOS/tvOS only)
    
    #if os(iOS) || os(tvOS)
    private func setupAudioSession() {
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
    private func setupRemoteCommandCenter() {
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
                self.pause()
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
    private func setupNotifications() {
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
                pause()
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
            // Headphones unplugged - pause playback
            if isPlaying {
                pause()
            }
            
        case .newDeviceAvailable:
            // New device connected - no action needed
            break
            
        default:
            break
        }
    }
    #endif
}

// MARK: - Convenience for views

extension AudioPlayerController {
    /// Provides access to the underlying player's audio buffer callback
    /// Used for visualization
    public func setAudioBufferHandler(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        player.onAudioBuffer = handler
    }
    
    /// Provides access to the underlying player's metadata callback
    public func setMetadataHandler(_ handler: @escaping ([String: String]) -> Void) {
        player.onMetadata = handler
    }
}

extension AudioPlayerController: PlaybackController {
    
    public var streamURL: URL {
        // Return the current URL or the default stream URL
        currentURL ?? defaultStreamURL ?? RadioStation.WXYC.streamURL
    }
    
    public func play(reason: String) throws {
        // AudioPlayerController uses the streamURL directly
        play(url: streamURL, reason: reason)
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
    
    // Explicit pause() to satisfy protocol (AudioPlayerController has pause(reason:))
    public func pause() {
        pause(reason: nil)
    }
}

#endif
