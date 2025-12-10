//
//  PlaybackControllerManager.swift
//  Playback
//
//  Manages the active PlaybackController and handles switching between controller types.
//  Reads the selected type from UserDefaults (persisted by PlayerControllerType).
//

import Foundation
import AVFoundation
import Core

#if !os(watchOS)
import AVAudioStreamer
import MiniMP3Streamer

/// Factory closure type for creating PlaybackController instances
public typealias PlaybackControllerFactory = @MainActor (PlayerControllerType) -> any PlaybackController

/// Manages the active PlaybackController and handles switching between implementations.
/// Observes the persisted PlayerControllerType and creates the appropriate controller.
@MainActor
@Observable
public final class PlaybackControllerManager {
    
    // MARK: - Singleton
    
    public static let shared = PlaybackControllerManager()
    
    // MARK: - Public Properties
    
    /// The currently active playback controller
    public private(set) var current: any PlaybackController
    
    /// The type of the current controller
    public private(set) var currentType: PlayerControllerType
    
    /// Convenience: whether audio is currently playing
    public var isPlaying: Bool { current.isPlaying }
    
    /// Convenience: whether playback is loading
    public var isLoading: Bool { current.isLoading }
    
    // MARK: - Private Properties
    
    private var audioBufferHandler: ((AVAudioPCMBuffer) -> Void)?
    private var metadataHandler: (([String: String]) -> Void)?
    private let controllerFactory: PlaybackControllerFactory
    
    // MARK: - Initialization
    
    /// Private initializer for singleton
    private init() {
        let type = PlayerControllerType.loadPersisted()
        self.currentType = type
        self.controllerFactory = Self.defaultFactory
        self.current = Self.defaultFactory(type)
    }
    
    /// Internal initializer for testing with dependency injection
    /// - Parameters:
    ///   - initialType: The initial controller type
    ///   - factory: Factory closure to create controllers
    internal init(initialType: PlayerControllerType, factory: @escaping PlaybackControllerFactory) {
        self.currentType = initialType
        self.controllerFactory = factory
        self.current = factory(initialType)
    }
    
    // MARK: - Controller Factory
    
    /// Default factory that creates real PlaybackController instances
    public static let defaultFactory: PlaybackControllerFactory = { type in
        switch type {
        case .radioPlayer:
            return RadioPlayerController()
        case .audioPlayer:
            return AudioPlayerController.shared
        case .avAudioStreamer:
            let config = AVAudioStreamerConfiguration(url: RadioStation.WXYC.streamURL)
            return AVAudioStreamer(configuration: config)
        case .miniMP3Streamer:
            let config = MiniMP3StreamerConfiguration(url: RadioStation.WXYC.streamURL)
            return MiniMP3Streamer(configuration: config)
        #if canImport(FfmpegAudio)
        case .ffmpegAudio:
            return FfmpegAudioController(streamURL: RadioStation.WXYC.streamURL)
        #endif
        }
    }
    
    // MARK: - Public Methods
    
    /// Switch to a different controller type
    /// - Parameter type: The new controller type to use
    public func switchTo(_ type: PlayerControllerType) {
        guard type != currentType else { return }
        
        // Stop current playback
        let wasPlaying = current.isPlaying
        if wasPlaying {
            current.stop()
        }
        
        // Create new controller using the factory
        let newController = controllerFactory(type)
        
        // Transfer handlers to new controller
        if let handler = audioBufferHandler {
            newController.setAudioBufferHandler(handler)
        }
        if let handler = metadataHandler {
            newController.setMetadataHandler(handler)
        }
        
        // Update state
        current = newController
        currentType = type
        
        // Resume playback if it was playing
        if wasPlaying {
            try? current.play(reason: "controller_switch")
        }
    }
    
    /// Toggle playback state
    public func toggle() {
        try? current.toggle(reason: "user_toggle")
    }
    
    /// Start playback
    public func play() {
        try? current.play(reason: "user_play")
    }
    
    /// Pause playback
    public func pause() {
        current.pause()
    }
    
    /// Stop playback
    public func stop() {
        current.stop()
    }
    
    /// Set the audio buffer handler (for visualization)
    /// This handler is preserved across controller switches
    public func setAudioBufferHandler(_ handler: @escaping (AVAudioPCMBuffer) -> Void) {
        audioBufferHandler = handler
        current.setAudioBufferHandler(handler)
    }
    
    /// Set the metadata handler
    /// This handler is preserved across controller switches
    public func setMetadataHandler(_ handler: @escaping ([String: String]) -> Void) {
        metadataHandler = handler
        current.setMetadataHandler(handler)
    }
    
    #if os(iOS)
    /// Handle app entering background
    public func handleAppDidEnterBackground() {
        current.handleAppDidEnterBackground()
    }
    
    /// Handle app returning to foreground
    public func handleAppWillEnterForeground() {
        current.handleAppWillEnterForeground()
    }
    #endif
}

#endif // !os(watchOS)
