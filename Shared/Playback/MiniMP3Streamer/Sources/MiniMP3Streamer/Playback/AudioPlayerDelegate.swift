import Foundation

/// Delegate for audio player events
protocol AudioPlayerDelegate: AnyObject, Sendable {
    /// Called when playback starts
    func audioPlayerDidStartPlaying(_ player: AudioEnginePlayer)

    /// Called when playback is paused
    func audioPlayerDidPause(_ player: AudioEnginePlayer)

    /// Called when playback stops
    func audioPlayerDidStop(_ player: AudioEnginePlayer)

    /// Called when an error occurs during playback
    func audioPlayer(_ player: AudioEnginePlayer, didEncounterError error: Error)

    /// Called when the player needs more buffers
    func audioPlayerNeedsMoreBuffers(_ player: AudioEnginePlayer)
}
