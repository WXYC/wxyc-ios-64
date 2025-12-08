import Foundation
@preconcurrency import AVFoundation
import AudioToolbox

/// Errors that can occur during MP3 decoding
enum MP3DecoderError: Error {
    case converterCreationFailed(OSStatus)
    case conversionFailed(OSStatus)
    case invalidFormat
    case bufferAllocationFailed
}

/// Decodes streaming MP3 data to PCM buffers using AudioToolbox
final class MP3StreamDecoder: @unchecked Sendable {
    private weak var delegate: (any MP3DecoderDelegate)?
    private let decoderQueue: DispatchQueue
    private let converterBox: AudioConverterBox
    private let bufferBox: DataBufferBox
    private let formatBox: FormatBox

    // Output format: 44.1kHz, stereo, Float32
    private let outputFormat: AVAudioFormat

    init(delegate: any MP3DecoderDelegate) {
        self.delegate = delegate
        self.decoderQueue = DispatchQueue(label: "com.avaudiostreamer.mp3decoder", qos: .userInitiated)
        self.converterBox = AudioConverterBox()
        self.bufferBox = DataBufferBox()
        self.formatBox = FormatBox()

        // Standard output format for decoded audio
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 2,
            interleaved: false
        ) else {
            fatalError("Failed to create output audio format")
        }
        self.outputFormat = format
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
            if let converter = self.converterBox.converter {
                AudioConverterDispose(converter)
                self.converterBox.converter = nil
            }
        }
    }

    private func processMP3Data(_ newData: Data) {
        // Append new data to buffer
        bufferBox.append(newData)

        // Try to parse audio format if we haven't yet
        if formatBox.inputFormat == nil {
            if let format = parseMP3Format(from: bufferBox.data) {
                formatBox.inputFormat = format
                setupConverter(inputFormat: format)
            } else {
                // Not enough data yet to determine format
                return
            }
        }

        // Convert MP3 data to PCM
        convertToPCM()
    }

    private func parseMP3Format(from data: Data) -> AudioStreamBasicDescription? {
        // Look for MP3 sync word (0xFFE or 0xFFF in the first 12 bits)
        guard data.count >= 4 else { return nil }

        var bytes = [UInt8](repeating: 0, count: min(data.count, 1024))
        data.copyBytes(to: &bytes, count: bytes.count)

        // Find MP3 frame header
        for i in 0..<(bytes.count - 4) {
            if (bytes[i] == 0xFF) && ((bytes[i + 1] & 0xE0) == 0xE0) {
                // Found sync word, parse MP3 header
                return parseMP3Header(bytes: Array(bytes[i..<min(i + 4, bytes.count)]))
            }
        }

        return nil
    }

    private func parseMP3Header(bytes: [UInt8]) -> AudioStreamBasicDescription? {
        guard bytes.count >= 4 else { return nil }

        // Parse MP3 frame header
        let byte1 = bytes[1]

        // Version (bits 3-4)
        let version = (byte1 >> 3) & 0x03

        // Layer (bits 1-2)
        _ = (byte1 >> 1) & 0x03  // Layer not currently used

        // Sample rate
        let sampleRates: [[Double]] = [
            [11025, 12000, 8000, 0],    // MPEG 2.5
            [0, 0, 0, 0],                // Reserved
            [22050, 24000, 16000, 0],   // MPEG 2
            [44100, 48000, 32000, 0]    // MPEG 1
        ]

        let byte2 = bytes[2]
        let sampleRateIndex = (byte2 >> 2) & 0x03
        let sampleRate = sampleRates[Int(version)][Int(sampleRateIndex)]

        guard sampleRate > 0 else { return nil }

        // Channel mode (bits 6-7 of byte 3)
        let byte3 = bytes[3]
        let channelMode = (byte3 >> 6) & 0x03
        let channels: UInt32 = (channelMode == 3) ? 1 : 2  // 3 = mono, others = stereo

        var format = AudioStreamBasicDescription()
        format.mFormatID = kAudioFormatMPEGLayer3
        format.mSampleRate = sampleRate
        format.mChannelsPerFrame = channels
        format.mFormatFlags = 0

        return format
    }

    private func setupConverter(inputFormat: AudioStreamBasicDescription) {
        var inputFormatCopy = inputFormat
        var outputFormatCopy = outputFormat.streamDescription.pointee

        var converter: AudioConverterRef?
        let status = AudioConverterNew(&inputFormatCopy, &outputFormatCopy, &converter)

        guard status == noErr, let audioConverter = converter else {
            notifyError(MP3DecoderError.converterCreationFailed(status))
            return
        }

        converterBox.converter = audioConverter
    }

    private func convertToPCM() {
        guard let converter = converterBox.converter else { return }
        guard bufferBox.data.count > 0 else { return }

        // Create output buffer
        let frameCapacity = AVAudioFrameCount(4096)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            notifyError(MP3DecoderError.bufferAllocationFailed)
            return
        }

        // Prepare for conversion
        let context = ConversionContext(inputData: bufferBox.data, inputOffset: 0)
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()

        var outputBufferList = pcmBuffer.mutableAudioBufferList.pointee
        var ioOutputDataPacketSize = frameCapacity

        let status = AudioConverterFillComplexBuffer(
            converter,
            { (
                inAudioConverter: AudioConverterRef,
                ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
                ioData: UnsafeMutablePointer<AudioBufferList>,
                outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
                inUserData: UnsafeMutableRawPointer?
            ) -> OSStatus in
                guard let userData = inUserData else { return kAudioConverterErr_InvalidInputSize }

                let context = Unmanaged<ConversionContext>.fromOpaque(userData).takeUnretainedValue()
                let remainingBytes = context.inputData.count - context.inputOffset

                guard remainingBytes > 0 else {
                    ioNumberDataPackets.pointee = 0
                    return noErr
                }

                // Provide input data
                let bytesToCopy = min(remainingBytes, Int(ioNumberDataPackets.pointee) * 1024)
                let bufferPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytesToCopy)

                context.inputData.copyBytes(
                    to: bufferPointer,
                    from: context.inputOffset..<(context.inputOffset + bytesToCopy)
                )

                ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(bufferPointer)
                ioData.pointee.mBuffers.mDataByteSize = UInt32(bytesToCopy)
                ioData.pointee.mNumberBuffers = 1

                ioNumberDataPackets.pointee = UInt32(bytesToCopy)
                context.inputOffset += bytesToCopy

                return noErr
            },
            contextPointer,
            &ioOutputDataPacketSize,
            &outputBufferList,
            nil
        )

        if status == noErr && ioOutputDataPacketSize > 0 {
            pcmBuffer.frameLength = ioOutputDataPacketSize

            // Remove processed data from buffer
            let bytesConsumed = context.inputOffset
            if bytesConsumed > 0 {
                bufferBox.removePrefix(bytesConsumed)
            }

            // Notify delegate
            notifyDelegate { [weak self] in
                guard let self = self else { return }
                self.delegate?.mp3Decoder(self, didDecode: pcmBuffer)
            }
        } else if status != noErr {
            // Clear some data to avoid getting stuck
            let clearAmount = min(1024, bufferBox.data.count)
            bufferBox.removePrefix(clearAmount)
        }
    }

    private func notifyDelegate(_ closure: @Sendable @escaping () -> Void) {
        Task { @MainActor in
            closure()
        }
    }

    private func notifyError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.delegate?.mp3Decoder(self, didEncounterError: error)
        }
    }
}

// MARK: - Supporting Types

private final class ConversionContext {
    let inputData: Data
    var inputOffset: Int

    init(inputData: Data, inputOffset: Int) {
        self.inputData = inputData
        self.inputOffset = inputOffset
    }
}

private final class AudioConverterBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _converter: AudioConverterRef?

    var converter: AudioConverterRef? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _converter
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _converter = newValue
        }
    }
}

private final class DataBufferBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _data = Data()

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return _data
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
            _data = _data.advanced(by: count)
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
    private var _inputFormat: AudioStreamBasicDescription?

    var inputFormat: AudioStreamBasicDescription? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _inputFormat
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _inputFormat = newValue
        }
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _inputFormat = nil
    }
}
