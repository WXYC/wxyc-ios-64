import Foundation
@preconcurrency import AVFoundation
@testable import AVAudioStreamer

#if !os(watchOS)

/// Events that can be emitted by AudioEnginePlayer via its delegate
enum AudioPlayerEvent: Sendable, Equatable {
    case didStartPlaying
    case didPause
    case didStop
    case didEncounterError(String) // Store error description for equality
    case needsMoreBuffers
    case didStall
    case didRecoverFromStall

    static func == (lhs: AudioPlayerEvent, rhs: AudioPlayerEvent) -> Bool {
        switch (lhs, rhs) {
        case (.didStartPlaying, .didStartPlaying),
             (.didPause, .didPause),
             (.didStop, .didStop),
             (.needsMoreBuffers, .needsMoreBuffers),
             (.didStall, .didStall),
             (.didRecoverFromStall, .didRecoverFromStall):
            true
        case let (.didEncounterError(lhsDesc), .didEncounterError(rhsDesc)):
            lhsDesc == rhsDesc
        default:
            false
        }
    }
}

/// Mock delegate for AudioEnginePlayer that captures events via AsyncStream
@MainActor
final class MockAudioPlayerDelegate: @preconcurrency AudioPlayerDelegate {
    private let eventContinuation: AsyncStream<AudioPlayerEvent>.Continuation
    let eventStream: AsyncStream<AudioPlayerEvent>

    init() {
        var continuation: AsyncStream<AudioPlayerEvent>.Continuation!
        eventStream = AsyncStream { continuation = $0 }
        eventContinuation = continuation
    }

    deinit {
        eventContinuation.finish()
    }

    nonisolated func audioPlayerDidStartPlaying(_ player: AudioEnginePlayer) {
        eventContinuation.yield(.didStartPlaying)
    }

    nonisolated func audioPlayerDidPause(_ player: AudioEnginePlayer) {
        eventContinuation.yield(.didPause)
    }

    nonisolated func audioPlayerDidStop(_ player: AudioEnginePlayer) {
        eventContinuation.yield(.didStop)
    }

    nonisolated func audioPlayer(_ player: AudioEnginePlayer, didEncounterError error: Error) {
        eventContinuation.yield(.didEncounterError(error.localizedDescription))
    }

    nonisolated func audioPlayerNeedsMoreBuffers(_ player: AudioEnginePlayer) {
        eventContinuation.yield(.needsMoreBuffers)
    }

    nonisolated func audioPlayerDidStall(_ player: AudioEnginePlayer) {
        eventContinuation.yield(.didStall)
    }

    nonisolated func audioPlayerDidRecoverFromStall(_ player: AudioEnginePlayer) {
        eventContinuation.yield(.didRecoverFromStall)
    }
}

#endif
