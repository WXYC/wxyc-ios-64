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
import PlaybackCore
import RadioPlayer
import AVAudioStreamer

#if !os(watchOS)

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
    
    /// Stream of audio buffers for visualization
    public var audioBufferStream: AsyncStream<AVAudioPCMBuffer> {
        audioBufferStreamContinuation.0
    }
    
    // MARK: - Private Properties
    
    private let controllerFactory: PlaybackControllerFactory
    private let analytics: PlaybackAnalytics
    private let metricsAdapter: StreamerMetricsAdapter
    
    private let audioBufferStreamContinuation: (AsyncStream<AVAudioPCMBuffer>, AsyncStream<AVAudioPCMBuffer>.Continuation) = {
        var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation!
        let stream = AsyncStream<AVAudioPCMBuffer>(bufferingPolicy: .bufferingNewest(1)) { c in
            continuation = c
        }
        return (stream, continuation)
    }()
    
    private var bufferConsumptionTask: Task<Void, Never>?
    
    // CPU Monitoring
    private var cpuMonitor: CPUMonitor?

    // MARK: - Initialization

    /// Private initializer for singleton
    private init() {
        let type = PlayerControllerType.loadPersisted()
        let analytics = PostHogPlaybackAnalytics.shared

        self.currentType = type
        self.controllerFactory = Self.defaultFactory
        self.analytics = analytics
        self.metricsAdapter = StreamerMetricsAdapter(analytics: analytics)
        
        let controller = Self.defaultFactory(type)
        self.current = controller

        wireUpMetricsAdapter(for: controller)
        startConsumingBuffers(from: controller)

        // Setup CPU Monitor
        self.cpuMonitor = CPUMonitor { [weak self] usage in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let event = CPUUsageEvent(
                    playerType: self.currentType,
                    cpuUsage: usage
                )
                self.analytics.capture(event)
            }
        }
    }

    /// Internal initializer for testing with dependency injection
    /// - Parameters:
    ///   - initialType: The initial controller type
    ///   - factory: Factory closure to create controllers
    ///   - analytics: Analytics instance to use
    internal init(
        initialType: PlayerControllerType,
        factory: @escaping PlaybackControllerFactory,
        analytics: PlaybackAnalytics = PostHogPlaybackAnalytics.shared
    ) {
        self.currentType = initialType
        self.controllerFactory = factory
        self.analytics = analytics
        self.metricsAdapter = StreamerMetricsAdapter(analytics: analytics)

        let controller = factory(initialType)
        self.current = controller

        wireUpMetricsAdapter(for: controller)
        startConsumingBuffers(from: controller)
    }
    
    // MARK: - Controller Factory
    
    /// Default factory that creates real PlaybackController instances
    public static let defaultFactory: PlaybackControllerFactory = { type in
        switch type {
        case .radioPlayer:
            return RadioPlayerController()
        case .avAudioStreamer:
            let config = AVAudioStreamerConfiguration(url: RadioStation.WXYC.streamURL)
            return AVAudioStreamer(configuration: config)
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
        
        wireUpMetricsAdapter(for: newController)
        
        // Update state
        current = newController
        currentType = type
    
        // Switch stream consumption
        startConsumingBuffers(from: newController)
        
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
        cpuMonitor?.start()
        try? current.play(reason: "user_play")
    }

    /// Stop playback
    public func stop() {
        cpuMonitor?.stop()
        current.stop()
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

    private func wireUpMetricsAdapter(for controller: any PlaybackController) {
        if let streamer = controller as? AVAudioStreamer {
            streamer.delegate = metricsAdapter
        }
    }

    private func startConsumingBuffers(from controller: any PlaybackController) {
        bufferConsumptionTask?.cancel()
        bufferConsumptionTask = Task { [weak self] in
            guard let self else { return }
            let continuation = audioBufferStreamContinuation.1
            // Use the stream from the controller
            // Note: If controller changes, this task is cancelled by new call.
            for await buffer in controller.audioBufferStream {
                continuation.yield(buffer)
            }
        }
    }
}

#endif // !os(watchOS)
