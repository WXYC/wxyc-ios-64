import Foundation
import CMiniMP3

/// Information about a decoded MP3 frame
struct MP3FrameInfo: Sendable {
    /// Number of bytes consumed from the input buffer
    let frameBytes: Int
    /// Number of audio channels (1 = mono, 2 = stereo)
    let channels: Int
    /// Sample rate in Hz (e.g., 44100, 48000, 32000)
    let sampleRate: Int
    /// MPEG layer (1, 2, or 3)
    let layer: Int
    /// Bitrate in kbps
    let bitrate: Int
}

/// Result of a frame decode operation
enum MP3DecodeResult: Sendable {
    /// Successfully decoded samples with frame info
    case decoded(samples: [Float], info: MP3FrameInfo)
    /// No valid MP3 data found, but some bytes were skipped (e.g., ID3 tags)
    case skipped(bytes: Int)
    /// Insufficient data to decode a frame
    case needMoreData
}

/// Swift wrapper for minimp3 decoder
///
/// This class provides a Swift-friendly interface to the minimp3 C library.
/// It decodes MP3 frames one at a time, outputting float PCM samples.
final class MiniMP3Decoder: @unchecked Sendable {
    private var decoder = mp3dec_t()
    private let lock = NSLock()
    
    /// Maximum samples per frame: 1152 samples * 2 channels
    private static let maxSamplesPerFrame = Int(MINIMP3_MAX_SAMPLES_PER_FRAME)
    
    /// Buffer for decoded PCM samples
    private var pcmBuffer: [Float]
    
    init() {
        pcmBuffer = [Float](repeating: 0, count: Self.maxSamplesPerFrame)
        mp3dec_init(&decoder)
    }
    
    /// Decode one MP3 frame from the input data
    ///
    /// - Parameter data: Input MP3 data buffer. Should contain at least one complete frame.
    ///   For reliable sync, minimp3 recommends having ~16KB (10 consecutive frames) available.
    /// - Returns: Decode result indicating success, skip, or need for more data
    func decodeFrame(from data: Data) -> MP3DecodeResult {
        lock.lock()
        defer { lock.unlock() }
        
        guard !data.isEmpty else {
            return .needMoreData
        }
        
        var info = mp3dec_frame_info_t()
        
        let sampleCount = data.withUnsafeBytes { ptr -> Int32 in
            guard let baseAddress = ptr.baseAddress else { return 0 }
            let mp3Ptr = baseAddress.assumingMemoryBound(to: UInt8.self)
            return mp3dec_decode_frame(
                &decoder,
                mp3Ptr,
                Int32(data.count),
                &pcmBuffer,
                &info
            )
        }
        
        // Check frame_bytes to understand what happened
        let frameBytes = Int(info.frame_bytes)
        
        if frameBytes == 0 {
            // Insufficient data to decode
            return .needMoreData
        }
        
        if sampleCount == 0 {
            // Decoder skipped invalid data or ID3 tags
            return .skipped(bytes: frameBytes)
        }
        
        // Successfully decoded samples
        let totalSamples = Int(sampleCount) * Int(info.channels)
        let samples = Array(pcmBuffer.prefix(totalSamples))
        
        let frameInfo = MP3FrameInfo(
            frameBytes: frameBytes,
            channels: Int(info.channels),
            sampleRate: Int(info.hz),
            layer: Int(info.layer),
            bitrate: Int(info.bitrate_kbps)
        )
        
        return .decoded(samples: samples, info: frameInfo)
    }
    
    /// Reset the decoder state
    ///
    /// Call this when seeking or switching streams to clear internal buffers.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        mp3dec_init(&decoder)
    }
}
