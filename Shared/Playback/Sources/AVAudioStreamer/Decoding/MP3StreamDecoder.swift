#if !os(watchOS)

import Foundation
@preconcurrency import AVFoundation
import AudioToolbox

/// Errors that can occur during MP3 decoding
enum MP3DecoderError: Error {
    case converterCreationFailed(OSStatus)
    case conversionFailed(OSStatus)
    case invalidFormat
    case bufferAllocationFailed
    case audioFileStreamError(OSStatus)
}

/// Context for C callbacks that safely holds a weak reference to the decoder
private final class AudioStreamContext {
    weak var decoder: MP3StreamDecoder?

    init(decoder: MP3StreamDecoder) {
        self.decoder = decoder
    }
}

/// Decodes streaming MP3 data to PCM buffers using AudioToolbox's AudioFileStream
final class MP3StreamDecoder: @unchecked Sendable {
    private nonisolated(unsafe) static var nextInstanceID = 0
    private let instanceID: Int

    private let decoderQueue: DispatchQueue

    /// Stream of decoded PCM buffers
    let decodedBufferStream: AsyncStream<AVAudioPCMBuffer>
    private let bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    /// Stream of decoding errors
    let errorStream: AsyncStream<Error>
    private let errorContinuation: AsyncStream<Error>.Continuation

    /// The AudioFileStream for parsing MP3 packets
    private var audioFileStream: AudioFileStreamID?

    /// The AudioConverter for MP3 to PCM conversion
    private var converter: AudioConverterRef?

    /// Parsed input format from the MP3 stream
    private var inputFormat: AudioStreamBasicDescription?

    /// Accumulated packets waiting to be decoded
    private var packetData = Data()
    private var packetDescriptions: [AudioStreamPacketDescription] = []

    // Output format: 44.1kHz, stereo, Float32
    private let outputFormat: AVAudioFormat

    /// Context for C callbacks - retained to prevent deallocation
    private var callbackContext: AudioStreamContext?

    init() {
        self.instanceID = Self.nextInstanceID
        Self.nextInstanceID += 1
        self.decoderQueue = DispatchQueue(label: "com.avaudiostreamer.mp3decoder.\(instanceID)", qos: .userInitiated)

        // Initialize buffer stream
        var bufferCont: AsyncStream<AVAudioPCMBuffer>.Continuation!
        self.decodedBufferStream = AsyncStream(bufferingPolicy: .unbounded) { bufferCont = $0 }
        self.bufferContinuation = bufferCont

        // Initialize error stream
        var errorCont: AsyncStream<Error>.Continuation!
        self.errorStream = AsyncStream(bufferingPolicy: .unbounded) { errorCont = $0 }
        self.errorContinuation = errorCont

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

    deinit {
        if let stream = audioFileStream {
            AudioFileStreamClose(stream)
        }
        if let conv = converter {
            AudioConverterDispose(conv)
        }
        // Release the retained context
        if callbackContext != nil {
            // The context was retained when passed to AudioFileStreamOpen
            // Release that retain count here
            Unmanaged.passUnretained(callbackContext!).release()
        }
        bufferContinuation.finish()
        errorContinuation.finish()
    }

    func decode(data: Data) {
        decoderQueue.async { [weak self] in
            guard let self else { return }
            self.processMP3Data(data)
        }
    }

    func reset() {
        decoderQueue.async { [weak self] in
            guard let self else { return }
            self.packetData.removeAll()
            self.packetDescriptions.removeAll()
            self.inputFormat = nil

            if let stream = self.audioFileStream {
                AudioFileStreamClose(stream)
                self.audioFileStream = nil
            }
            if let conv = self.converter {
                AudioConverterDispose(conv)
                self.converter = nil
            }
        }
    }

    private func processMP3Data(_ newData: Data) {
        // Set up AudioFileStream if needed
        if audioFileStream == nil {
            var stream: AudioFileStreamID?

            // Create context with weak reference to self
            let context = AudioStreamContext(decoder: self)
            self.callbackContext = context
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            let status = AudioFileStreamOpen(
                contextPtr,
                { (inClientData, inAudioFileStream, inPropertyID, ioFlags) in
                    let context = Unmanaged<AudioStreamContext>.fromOpaque(inClientData).takeUnretainedValue()
                    guard let decoder = context.decoder else { return }
                    decoder.handlePropertyChange(propertyID: inPropertyID)
                },
                { (inClientData, inNumberBytes, inNumberPackets, inInputData, inPacketDescriptions) in
                    let context = Unmanaged<AudioStreamContext>.fromOpaque(inClientData).takeUnretainedValue()
                    guard let decoder = context.decoder else { return }
                    decoder.handlePackets(
                        numberBytes: inNumberBytes,
                        numberPackets: inNumberPackets,
                        inputData: inInputData,
                        packetDescriptions: inPacketDescriptions
                    )
                },
                kAudioFileMP3Type,
                &stream
            )

            guard status == noErr, let fileStream = stream else {
                errorContinuation.yield(MP3DecoderError.audioFileStreamError(status))
                return
            }

            audioFileStream = fileStream
        }

        // Parse the MP3 data
        guard let stream = audioFileStream else { return }

        newData.withUnsafeBytes { rawBufferPointer in
            guard let bytes = rawBufferPointer.baseAddress else { return }
            let status = AudioFileStreamParseBytes(
                stream,
                UInt32(newData.count),
                bytes,
                []
            )
            if status != noErr && status != kAudioFileStreamError_NotOptimized {
                // NotOptimized is not fatal for streaming
            }
        }
    }

    private func handlePropertyChange(propertyID: AudioFileStreamPropertyID) {
        guard propertyID == kAudioFileStreamProperty_DataFormat else { return }
        guard let stream = audioFileStream else { return }

        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)

        let status = AudioFileStreamGetProperty(
            stream,
            kAudioFileStreamProperty_DataFormat,
            &formatSize,
            &format
        )

        guard status == noErr else { return }

        inputFormat = format
        setUpConverter(inputFormat: format)
    }

    private func handlePackets(
        numberBytes: UInt32,
        numberPackets: UInt32,
        inputData: UnsafeRawPointer,
        packetDescriptions: UnsafePointer<AudioStreamPacketDescription>?
    ) {
        guard numberPackets > 0 else { return }

        // Accumulate packet data
        let data = Data(bytes: inputData, count: Int(numberBytes))
        packetData.append(data)

        // Accumulate packet descriptions (adjusting offsets)
        if let descriptions = packetDescriptions {
            let currentOffset = Int64(packetData.count) - Int64(numberBytes)
            for i in 0..<Int(numberPackets) {
                var desc = descriptions[i]
                desc.mStartOffset += currentOffset
                self.packetDescriptions.append(desc)
            }
        }

        // Decode all available packets into PCM buffers
        // Use a small threshold to minimize latency while ensuring enough data for conversion
        while self.packetDescriptions.count >= 4 {
            convertToPCM()
        }
    }

    private func setUpConverter(inputFormat: AudioStreamBasicDescription) {
        var inputFormatCopy = inputFormat
        var outputFormatCopy = outputFormat.streamDescription.pointee

        var newConverter: AudioConverterRef?
        let status = AudioConverterNew(&inputFormatCopy, &outputFormatCopy, &newConverter)

        guard status == noErr, let audioConverter = newConverter else {
            errorContinuation.yield(MP3DecoderError.converterCreationFailed(status))
            return
        }

        converter = audioConverter
    }

    private func convertToPCM() {
        guard let converter else { return }
        guard !packetDescriptions.isEmpty else { return }

        // Create output buffer
        let frameCapacity = AVAudioFrameCount(4096)
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCapacity) else {
            errorContinuation.yield(MP3DecoderError.bufferAllocationFailed)
            return
        }

        // Set up output buffer sizes
        let bytesPerChannel = UInt32(frameCapacity) * UInt32(MemoryLayout<Float>.size)
        let audioBufferList = pcmBuffer.mutableAudioBufferList
        let bufferListPtr = UnsafeMutableAudioBufferListPointer(audioBufferList)
        for i in 0..<Int(audioBufferList.pointee.mNumberBuffers) {
            bufferListPtr[i].mDataByteSize = bytesPerChannel
        }

        // Create context for the callback
        let context = ConversionContext(
            packetData: packetData,
            packetDescriptions: packetDescriptions
        )
        let contextPointer = Unmanaged.passUnretained(context).toOpaque()

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
                guard let userData = inUserData else {
                    ioNumberDataPackets.pointee = 0
                    return kAudioConverterErr_InvalidInputSize
                }

                let context = Unmanaged<ConversionContext>.fromOpaque(userData).takeUnretainedValue()

                guard context.packetIndex < context.packetDescriptions.count else {
                    ioNumberDataPackets.pointee = 0
                    return noErr
                }

                // Provide one packet at a time
                let desc = context.packetDescriptions[context.packetIndex]
                let packetSize = Int(desc.mDataByteSize)
                let packetOffset = Int(desc.mStartOffset)
                let dataCount = context.packetData.count

                // Validate bounds carefully to avoid overflow
                guard packetSize > 0,
                      packetOffset >= 0,
                      packetOffset < dataCount,
                      dataCount - packetOffset >= packetSize else {
                    ioNumberDataPackets.pointee = 0
                    return noErr
                }

                // Double-check: verify that the end of range <= count
                let endIndex = packetOffset + packetSize
                precondition(endIndex <= context.packetData.count,
                       "Range end \(endIndex) exceeds data count \(context.packetData.count)")

                // Copy packet data to our buffer using memcpy to avoid Data.copyBytes issues
                let bufferPointer = context.getBuffer(capacity: packetSize)
                context.packetData.withUnsafeBytes { rawBuffer in
                    guard let baseAddress = rawBuffer.baseAddress else { return }
                    memcpy(bufferPointer, baseAddress.advanced(by: packetOffset), packetSize)
                }

                ioData.pointee.mNumberBuffers = 1
                ioData.pointee.mBuffers.mData = UnsafeMutableRawPointer(bufferPointer)
                ioData.pointee.mBuffers.mDataByteSize = UInt32(packetSize)
                ioData.pointee.mBuffers.mNumberChannels = 0

                // Provide packet description
                if let outDesc = outDataPacketDescription {
                    let packetDesc = AudioStreamPacketDescription(
                        mStartOffset: 0,
                        mVariableFramesInPacket: desc.mVariableFramesInPacket,
                        mDataByteSize: desc.mDataByteSize
                    )
                    outDesc.pointee = context.setCurrentPacketDescription(packetDesc)
                }

                ioNumberDataPackets.pointee = 1
                context.packetIndex += 1

                return noErr
            },
            contextPointer,
            &ioOutputDataPacketSize,
            audioBufferList,
            nil
        )

        if status == noErr && ioOutputDataPacketSize > 0 {
            pcmBuffer.frameLength = ioOutputDataPacketSize

            // Clear consumed packets
            let consumedPackets = context.packetIndex
            if consumedPackets > 0 && consumedPackets <= packetDescriptions.count {
                // Find the end offset of consumed data
                let lastConsumedDesc = packetDescriptions[consumedPackets - 1]
                let consumedBytes = Int(lastConsumedDesc.mStartOffset + Int64(lastConsumedDesc.mDataByteSize))

                if consumedBytes > 0 && consumedBytes <= packetData.count {
                    packetData.removeFirst(consumedBytes)

                    // Adjust remaining packet descriptions
                    packetDescriptions.removeFirst(consumedPackets)
                    for i in 0..<packetDescriptions.count {
                        packetDescriptions[i].mStartOffset -= Int64(consumedBytes)
                    }
                }
            }

            // Yield the decoded buffer
            bufferContinuation.yield(pcmBuffer)
        } else if status != noErr && status != kAudioConverterErr_InvalidInputSize {
            // Only clear on non-recoverable errors
            packetDescriptions.removeAll()
            packetData.removeAll()
        }
    }
}

// MARK: - Supporting Types

private final class ConversionContext {
    let packetData: Data
    let packetDescriptions: [AudioStreamPacketDescription]
    var packetIndex: Int = 0

    /// Storage for current packet description - must remain valid between callback invocations
    private var packetDescriptionStorage: UnsafeMutablePointer<AudioStreamPacketDescription>

    private var buffer: UnsafeMutablePointer<UInt8>?
    private var bufferCapacity: Int = 0

    init(packetData: Data, packetDescriptions: [AudioStreamPacketDescription]) {
        self.packetData = packetData
        self.packetDescriptions = packetDescriptions
        self.packetDescriptionStorage = .allocate(capacity: 1)
    }

    deinit {
        buffer?.deallocate()
        packetDescriptionStorage.deallocate()
    }

    func getBuffer(capacity: Int) -> UnsafeMutablePointer<UInt8> {
        if capacity > bufferCapacity {
            buffer?.deallocate()
            bufferCapacity = max(capacity, 4096)
            buffer = .allocate(capacity: bufferCapacity)
        }
        return buffer!
    }

    func setCurrentPacketDescription(_ desc: AudioStreamPacketDescription) -> UnsafeMutablePointer<AudioStreamPacketDescription> {
        packetDescriptionStorage.pointee = desc
        return packetDescriptionStorage
    }
}

#endif
