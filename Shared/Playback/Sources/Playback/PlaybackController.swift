//
//  PlaybackController.swift
//  Core
//
//  Protocol defining the common interface for audio playback controllers.
//  Both RadioPlayerController and AudioPlayerController conform to this protocol,
//  enabling dependency injection and swappable implementations.
//

import Foundation
import AVFoundation
import SwiftUI

// MARK: - PlaybackController Protocol

/// Protocol defining the common interface for audio playback controllers.
///
/// This protocol enables swappable playback implementations, allowing the app to
/// choose between different audio playback backends (e.g., AVPlayer-based RadioPlayerController
/// vs. AudioStreaming-based AudioPlayerController).
///
/// RadioPlayerController is the canonical implementation - its behaviors define
/// the expected contract that conforming implementations must match.
@MainActor
public protocol PlaybackController: AnyObject, Observable {
    /// Whether audio is currently playing
    var isPlaying: Bool { get }
    
    /// Whether playback is loading (play initiated but not yet playing)
    /// Controllers without loading state should return `false`
    var isLoading: Bool { get }
    
    /// Starts playback with the given reason for analytics
    /// - Parameter reason: A description of why playback was started (for analytics)
    /// - Throws: If playback cannot be started
    func play(reason: String) throws
    
    /// Pauses playback
    func pause()
    
    /// Toggles between playing and paused states
    /// - Parameter reason: A description of why playback was toggled (for analytics)
    /// - Throws: If playback cannot be started when toggling from paused to playing
    func toggle(reason: String) throws
    
    /// Stops playback completely
    /// Controllers without a distinct stop state should treat this as pause
    func stop()
    
    /// Stream of audio buffers for visualization
    /// Controllers without audio buffer access should return an empty stream
    /// Should be buffered with .bufferingNewest(1) to avoid blocking audio thread
    var audioBufferStream: AsyncStream<AVAudioPCMBuffer> { get }
    
    #if os(iOS)
    /// Called when the app enters the background
    /// Should deactivate audio session if not playing
    func handleAppDidEnterBackground()
    
    /// Called when the app returns to the foreground
    /// Should reactivate audio session if playback is intended
    func handleAppWillEnterForeground()
    #endif
}

// MARK: - Environment Key

private struct PlaybackControllerKey: @MainActor EnvironmentKey {
    @MainActor static var defaultValue: (any PlaybackController)? = nil
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    /// The playback controller to use for audio playback
    @MainActor var playbackController: (any PlaybackController)? {
        get { self[PlaybackControllerKey.self] }
        set { self[PlaybackControllerKey.self] = newValue }
    }
}

