@preconcurrency import AVFoundation

/// Delegate for MP3 decoder events
protocol MP3DecoderDelegate: AnyObject, Sendable {
    /// Called when a PCM buffer has been decoded
    func mp3Decoder(_ decoder: MP3StreamDecoder, didDecode buffer: AVAudioPCMBuffer)

    /// Called when an error occurs during decoding
    func mp3Decoder(_ decoder: MP3StreamDecoder, didEncounterError error: Error)
}
