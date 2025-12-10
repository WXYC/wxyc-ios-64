@preconcurrency import AVFoundation

/// Delegate protocol for receiving audio streamer events
public protocol AVAudioStreamerDelegate: AnyObject, Sendable {
    /// Called when a PCM buffer is decoded and ready for processing
    /// - Parameters:
    ///   - buffer: The decoded PCM audio buffer
    ///   - time: The audio time associated with this buffer, if available
    func audioStreamer(didOutput buffer: AVAudioPCMBuffer, at time: AVAudioTime?)

    /// Called when the player state changes
    /// - Parameter state: The new state
    func audioStreamer(didChangeState state: StreamingAudioState)

    /// Called when an error occurs
    /// - Parameter error: The error that occurred
    func audioStreamer(didEncounterError error: Error)
}

/// Optional delegate methods
public extension AVAudioStreamerDelegate {
    func audioStreamer(didOutput buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {}
    func audioStreamer(didChangeState state: StreamingAudioState) {}
    func audioStreamer(didEncounterError error: Error) {}
}
