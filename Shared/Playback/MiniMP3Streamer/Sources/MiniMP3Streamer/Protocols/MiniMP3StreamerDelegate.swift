@preconcurrency import AVFoundation

/// Delegate protocol for receiving MiniMP3Streamer events
public protocol MiniMP3StreamerDelegate: AnyObject, Sendable {
    /// Called when a PCM buffer is decoded and ready for processing
    /// - Parameters:
    ///   - buffer: The decoded PCM audio buffer
    ///   - time: The audio time associated with this buffer, if available
    func miniMP3Streamer(didOutput buffer: AVAudioPCMBuffer, at time: AVAudioTime?)

    /// Called when the player state changes
    /// - Parameter state: The new state
    func miniMP3Streamer(didChangeState state: StreamingAudioState)

    /// Called when an error occurs
    /// - Parameter error: The error that occurred
    func miniMP3Streamer(didEncounterError error: Error)
}

/// Optional delegate methods
public extension MiniMP3StreamerDelegate {
    func miniMP3Streamer(didOutput buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {}
    func miniMP3Streamer(didChangeState state: StreamingAudioState) {}
    func miniMP3Streamer(didEncounterError error: Error) {}
}
