//
//  PlaybackController.swift
//  Playback
//
//  Protocol defining the common interface for audio playback controllers.
//  Both RadioPlayerController and AudioPlayerController conform to this protocol,
//  enabling dependency injection and swappable implementations.
//
//  Created by Jake Bromberg on 12/04/25.
//  Copyright © 2025 WXYC. All rights reserved.
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
    /// The current playback state
    ///
    /// This is the single source of truth for playback state.
    /// Use convenience properties like `state.isPlaying` for boolean checks.
    var state: PlaybackState { get }

    /// Whether audio is currently playing
    var isPlaying: Bool { get }

    /// Whether the listener has asked for audio, that request is still
    /// standing, and there is still something to cancel — set by
    /// `play(reason:)`, cleared by `stop(reason:)` or by the stream failing.
    ///
    /// This, not `isPlaying`, is what a play/pause control must render and act
    /// on. `isPlaying` answers whether audio is coming out, which is a
    /// different question: it is `false` for the whole duration of a start
    /// that has not yet produced sound. A control driven by it shows play
    /// while a start is in flight, so a tap meant to cancel that start
    /// re-issues it instead (Sentry IOS-4K/4M/4N).
    ///
    /// Rendering the icon and choosing the action from this one predicate is
    /// the point: a start that is still connecting is a *requested* playback
    /// the listener can cancel, which is what the pause icon has always
    /// promised.
    ///
    /// An error state reads `false` even though the controller's internal
    /// intent flag stays set (it has to — the reconnect ramp and the analytics
    /// session both live under a standing request). A failed start has nothing
    /// left to cancel, so the control must offer a retry instead of a stop.
    var isPlaybackRequested: Bool { get }

    /// Starts playback with the given reason for analytics
    /// - Parameter reason: Why playback was started (for analytics)
    /// - Throws: If playback cannot be started
    func play(reason: PlaybackReason) throws
    
    /// Toggles between playing and stopped states
    /// - Parameter reason: Why playback was toggled (for analytics)
    /// - Throws: If playback cannot be started when toggling from stopped to playing
    func toggle(reason: PlaybackReason) throws
    
    /// Stops playback and disconnects from stream
    /// For live streaming, this resets the connection so resume plays live audio
    /// - Parameter reason: Why playback was stopped (for analytics)
    func stop(reason: PlaybackReason)
    
    /// Creates a fresh stream of audio buffers for visualization.
    /// Each call returns a new stream; the previous stream's continuation is finished.
    /// Controllers without audio buffer access should return an empty finished stream.
    /// Should be buffered with .bufferingNewest(1) to avoid blocking audio thread.
    /// Only yields buffers when render tap is installed via `installRenderTap()`.
    func makeAudioBufferStream() -> AsyncStream<AVAudioPCMBuffer>

    /// Install the render tap for audio visualization.
    /// The tap runs at ~60Hz and consumes CPU, so only install when actively displaying visualizations.
    /// Controllers without render tap support should no-op.
    func installRenderTap()
    
    /// Remove the render tap when visualization is no longer needed.
    /// Controllers without render tap support should no-op.
    func removeRenderTap()
    
    #if os(iOS)
    /// Called when the app enters the background
    /// Should deactivate audio session if not playing
    func handleAppDidEnterBackground()

    /// Called when the app returns to the foreground
    /// Should reactivate audio session if playback is intended
    func handleAppWillEnterForeground()
    #endif
}
