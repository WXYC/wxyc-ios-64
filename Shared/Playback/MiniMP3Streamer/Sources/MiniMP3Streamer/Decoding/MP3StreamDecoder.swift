import Foundation
@preconcurrency import AVFoundation

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
    private let bufferBox: DataBufferBox
    private let formatBox: FormatBox
    
    /// Minimum buffer size for reliable MP3 sync (~10 consecutive frames)
    private static let minBufferSize = 16 * 1024
    
    init(delegate: any MP3DecoderDelegate) {
        self.delegate = delegate
        self.decoderQueue = DispatchQueue(label: "com.avaudiostreamer.mp3decoder", qos: .userInitiated)
        self.bufferBox = DataBufferBox()
        self.formatBox = FormatBox()
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
            self.bufferBox.clear()
            self.formatBox.clear()
            self.decoder.reset()
        }
    }
    
    private func processMP3Data(_ newData: Data) {
        // Append new data to buffer
        bufferBox.append(newData)
        
        // Wait for minimum buffer size on first decode for reliable sync
        if formatBox.format == nil && bufferBox.count < Self.minBufferSize {
            return
        }
        
        // Decode frames until we can't anymore
        decodeAvailableFrames()
    }
    
    private func decodeAvailableFrames() {
        while bufferBox.count > 0 {
            let inputData = bufferBox.data
            let result = decoder.decodeFrame(from: inputData)
            
            switch result {
            case .decoded(let samples, let info):
                // Remove consumed bytes from buffer
                bufferBox.removePrefix(info.frameBytes)
                
                // Set up format on first successful decode
                if formatBox.format == nil {
                    let format = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: Double(info.sampleRate),
                        channels: AVAudioChannelCount(info.channels),
                        interleaved: false
                    )
                    formatBox.format = format
                }
                
                // Convert to AVAudioPCMBuffer and notify delegate
                if let format = formatBox.format,
                   let pcmBuffer = createPCMBuffer(from: samples, info: info, format: format) {
                    notifyDelegate { [weak self] delegate in
                        guard let self = self else { return }
                        delegate.mp3Decoder(self, didDecode: pcmBuffer)
                    }
                }
                
            case .skipped(let bytes):
                // Remove skipped bytes (ID3 tags, invalid data)
                bufferBox.removePrefix(bytes)
                
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
        for frame in 0..<frameCount {
            for channel in 0..<channels {
                floatChannelData[channel][frame] = samples[frame * channels + channel]
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

// MARK: - Supporting Types

private final class DataBufferBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()
    
    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return _data
    }
    
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _data.count
    }
    
    func append(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        _data.append(newData)
    }
    
    func removePrefix(_ count: Int) {
        lock.lock()
        defer { lock.unlock() }
        if count >= _data.count {
            _data.removeAll()
        } else {
            _data = _data.dropFirst(count)
        }
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _data.removeAll()
    }
}

private final class FormatBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _format: AVAudioFormat?
    
    var format: AVAudioFormat? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _format
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _format = newValue
        }
    }
    
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _format = nil
    }
}
