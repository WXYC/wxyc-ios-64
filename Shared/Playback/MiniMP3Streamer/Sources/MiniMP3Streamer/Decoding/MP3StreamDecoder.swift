import Foundation
@preconcurrency import AVFoundation
import Accelerate

/// Errors that can occur during MP3 decoding
enum MP3DecoderError: Error {
    case bufferAllocationFailed
    case formatMismatch
    case decodingFailed
}

/// Decodes streaming MP3 data to PCM buffers using minimp3
final class MP3StreamDecoder: @unchecked Sendable {
    private weak var delegate: (any MP3DecoderDelegate)?
    private let decoderQueue: DispatchQueue
    private let decoder = MiniMP3Decoder()

    /// Accumulated MP3 data waiting to be decoded.
    /// Thread-safety: All access must be on `decoderQueue`.
    private var buffer = Data()

    /// The decoded audio format, set after first successful decode.
    /// Thread-safety: All access must be on `decoderQueue`.
    private var format: AVAudioFormat?

    /// Minimum buffer size for reliable MP3 sync (~10 consecutive frames)
    private static let minBufferSize = 16 * 1024

    init(delegate: any MP3DecoderDelegate) {
        self.delegate = delegate
        self.decoderQueue = DispatchQueue(label: "com.avaudiostreamer.mp3decoder", qos: .userInitiated)
    }
    
    func decode(data: Data) {
        decoderQueue.async { [weak self] in
            guard let self = self else { return }
            self.processMP3Data(data)
        }
    }
    
    func reset() {
        decoderQueue.async { [weak self] in
            guard let self = self else { return }
            self.buffer.removeAll()
            self.format = nil
            self.decoder.reset()
        }
    }
    
    private func processMP3Data(_ newData: Data) {
        // Append new data to buffer
        buffer.append(newData)

        // Wait for minimum buffer size on first decode for reliable sync
        if format == nil && buffer.count < Self.minBufferSize {
            return
        }

        // Decode frames until we can't anymore
        decodeAvailableFrames()
    }
    
    private func decodeAvailableFrames() {
        while buffer.count > 0 {
            let result = decoder.decodeFrame(from: buffer)

            switch result {
            case .decoded(let samples, let info):
                // Remove consumed bytes from buffer
                buffer.removeFirst(info.frameBytes)

                // Set up format on first successful decode
                if format == nil {
                    format = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: Double(info.sampleRate),
                        channels: AVAudioChannelCount(info.channels),
                        interleaved: false
                    )
                }

                // Convert to AVAudioPCMBuffer and notify delegate
                if let format = format,
                   let pcmBuffer = createPCMBuffer(from: samples, info: info, format: format) {
                    notifyDelegate { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.mp3Decoder(self, didDecode: pcmBuffer)
                    }
                }

            case .skipped(let bytes):
                // Remove skipped bytes (ID3 tags, invalid data)
                buffer.removeFirst(bytes)

            case .needMoreData:
                // Not enough data to decode another frame
                return
            }
        }
    }
    
    /// Create an AVAudioPCMBuffer from interleaved float samples
    private func createPCMBuffer(
        from samples: [Float],
        info: MP3FrameInfo,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let frameCount = samples.count / info.channels
        guard frameCount > 0 else { return nil }
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            notifyError(MP3DecoderError.bufferAllocationFailed)
            return nil
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // De-interleave samples into separate channel buffers
        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }

        let channels = info.channels

        samples.withUnsafeBufferPointer { samplesPtr in
            guard let baseAddress = samplesPtr.baseAddress else { return }

            if channels == 2 {
                // Use vDSP_ctoz for SIMD-accelerated stereo de-interleaving
                // Treats interleaved [L0,R0,L1,R1,...] as complex numbers
                // and splits into real (left) and imaginary (right) channels
                baseAddress.withMemoryRebound(to: DSPComplex.self, capacity: frameCount) { complexPtr in
                    var splitComplex = DSPSplitComplex(
                        realp: floatChannelData[0],
                        imagp: floatChannelData[1]
                    )
                    vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(frameCount))
                }
            } else if channels == 1 {
                // Mono: direct copy
                memcpy(floatChannelData[0], baseAddress, frameCount * MemoryLayout<Float>.size)
            }
        }

        return buffer
    }
    
    private func notifyDelegate(_ closure: @Sendable @escaping (_ delegate: any MP3DecoderDelegate) -> Void) {
        Task { @MainActor [weak self] in
            guard let delegate = self?.delegate else { return }
            closure(delegate)
        }
    }
    
    private func notifyError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self = self, let delegate = self.delegate else { return }
            delegate.mp3Decoder(self, didEncounterError: error)
        }
    }
}

