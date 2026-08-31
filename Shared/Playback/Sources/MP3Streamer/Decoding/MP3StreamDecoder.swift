//
//  MP3StreamDecoder.swift
//  Playback
//
//  Decodes MP3 audio data into PCM buffers using AudioToolbox.
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

#if !os(watchOS)

import Foundation
@preconcurrency import AVFoundation
import AudioToolbox
#if targetEnvironment(macCatalyst) || os(macOS)
import CoreAudio
#endif
import Core
import Logger
import Synchronization

/// Errors that can occur during MP3 decoding
enum MP3DecoderError: Error {
    case converterCreationFailed(OSStatus)
    case conversionFailed(OSStatus)
    case invalidFormat
    case bufferAllocationFailed
    case audioFileStreamError(OSStatus)
    /// The undecoded packet backlog reached ``MP3StreamDecoder/maxBufferedByteCount``
    /// and was dropped. Distinct from the other cases because it reports a decoder that
    /// is accumulating faster than it drains rather than a single failed operation: the
    /// dropped audio is a deliberate glitch, chosen over the unbounded growth that
    /// crashed the app in issue #1025.
    case backlogOverflow(droppedBytes: Int, droppedPackets: Int)
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
    private static let idLock = NSLock()
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
    private var packetDescriptions: Deque<AudioStreamPacketDescription> = []

    /// Tracks how many bytes from the start of packetData have been consumed.
    /// Used to avoid O(n) Data.removeFirst() on every decode cycle.
    private var consumedByteOffset: Int = 0

    /// Threshold for compacting the data buffer (64KB).
    /// When consumedByteOffset exceeds this, we perform the actual removal.
    private let compactionThreshold = 65536

    /// Hard ceiling on the bytes `packetData` may hold (4 MB).
    ///
    /// The append in `handlePackets()` is unconditional, while every path that drains
    /// `packetData` is conditional on a converter existing and consuming. When the
    /// converter is missing — `setUpConverter` only runs on a `kAudioFileStreamProperty_DataFormat`
    /// callback, and yields `converterCreationFailed` without one on failure — or when it
    /// stops consuming, nothing else bounds the buffer. A backgrounded session grew it to
    /// roughly 448 MB before `Data.append` failed to allocate (issue #1025, Sentry IOS-6P).
    ///
    /// 4 MB is about 256 seconds of the 128 kbps stream, or 64-256 network chunks (the
    /// HTTP layer delivers 16-64 KB at a time). That is far above any real jitter burst —
    /// the startup watchdog gives up after 12 seconds — and 64x `compactionThreshold`, so
    /// the healthy path never approaches it; and it is small enough that reaching it can
    /// never itself contribute to a memory-pressure kill.
    static let maxBufferedByteCount = 4 * 1024 * 1024

    /// How many times this decoder has dropped its backlog. Diagnostic only, and confined
    /// to `decoderQueue` like the rest of the buffering state.
    private var overflowCount = 0

    // Output format: 44.1kHz, stereo, Float32
    private let outputFormat: AVAudioFormat

    /// Context for C callbacks - retained to prevent deallocation
    private var callbackContext: AudioStreamContext?

    /// Thread-safe cancellation flag. Set by `reset()` to interrupt the conversion
    /// loop in `handlePackets()`, preventing unbounded blocking of the decoder queue.
    private let _isCancelled = Mutex(false)

    /// Whether this decoder has been cancelled via `reset()`.
    var isCancelled: Bool {
        _isCancelled.withLock { $0 }
    }

    init() {
        Self.idLock.lock()
        self.instanceID = Self.nextInstanceID
        Self.nextInstanceID += 1
        Self.idLock.unlock()
        self.decoderQueue = DispatchQueue(label: "com.avaudiostreamer.mp3decoder.\(instanceID)", qos: .userInitiated)

        // Initialize buffer stream with bounded buffer to prevent memory growth
        // 32 buffers is enough to handle temporary consumer slowdowns
        (self.decodedBufferStream, self.bufferContinuation) = AsyncStream.makeStream(
            of: AVAudioPCMBuffer.self,
            bufferingPolicy: .bufferingOldest(32)
        )

        // Initialize error stream - errors are rare, small buffer is fine
        (self.errorStream, self.errorContinuation) = AsyncStream.makeStream(
            of: Error.self,
            bufferingPolicy: .bufferingNewest(4)
        )

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

    /// Cancels any in-progress conversion loop and asynchronously resets the decoder state.
    ///
    /// The cancellation flag is set immediately (thread-safe), causing the conversion
    /// loop in `handlePackets()` to break on its next iteration. The actual cleanup
    /// is dispatched asynchronously to the decoder queue so it never blocks the caller.
    /// Callers should replace this decoder with a fresh instance after calling reset.
    func reset() {
        _isCancelled.withLock { $0 = true }

        decoderQueue.async { [self] in
            Log(.info, category: .playback, "MP3StreamDecoder[\(instanceID)] reset: cleaning up")
            packetData.removeAll()
            packetDescriptions.removeAll()
            consumedByteOffset = 0
            inputFormat = nil

            if let stream = audioFileStream {
                AudioFileStreamClose(stream)
                audioFileStream = nil
            }
            if let conv = converter {
                AudioConverterDispose(conv)
                converter = nil
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

        // Bound the backlog before appending to it. The append below is the only
        // unconditional write to `packetData`; every path that drains it is conditional on
        // a converter that exists and consumes, and nothing stops feeding the decoder when
        // there isn't one. Dropping the backlog costs a glitch — keeping it cost 896 MB
        // and the process (#1025).
        if packetData.count + Int(numberBytes) > Self.maxBufferedByteCount {
            dropBacklog(incomingByteCount: Int(numberBytes))
            // A single callback bigger than the whole cap cannot be usefully buffered even
            // against an empty buffer, so drop it too rather than start the next backlog
            // already over the ceiling.
            guard Int(numberBytes) <= Self.maxBufferedByteCount else { return }
        }

        // Calculate the base offset for these packets in our accumulated data
        let currentOffset = Int64(packetData.count)

        // Accumulate packet data
        let data = Data(bytes: inputData, count: Int(numberBytes))
        packetData.append(data)

        // Accumulate packet descriptions (adjusting offsets)
        if let descriptions = packetDescriptions {
            // VBR or streams that provide explicit descriptions
            for i in 0..<Int(numberPackets) {
                var desc = descriptions[i]
                desc.mStartOffset += currentOffset
                self.packetDescriptions.append(desc)
            }
        } else if let format = inputFormat, format.mBytesPerPacket > 0 {
            // CBR stream: packet descriptions are nil, calculate from format
            // For CBR, all packets have the same size (mBytesPerPacket)
            let bytesPerPacket = Int(format.mBytesPerPacket)
            for i in 0..<Int(numberPackets) {
                let desc = AudioStreamPacketDescription(
                    mStartOffset: currentOffset + Int64(i * bytesPerPacket),
                    mVariableFramesInPacket: 0,
                    mDataByteSize: format.mBytesPerPacket
                )
                self.packetDescriptions.append(desc)
            }
        } else if numberPackets > 0 && numberBytes > 0 {
            // Fallback: no format yet or unknown format, estimate packet size
            // This handles the case where packets arrive before format is detected
            let estimatedBytesPerPacket = numberBytes / numberPackets
            if estimatedBytesPerPacket > 0 {
                for i in 0..<Int(numberPackets) {
                    let desc = AudioStreamPacketDescription(
                        mStartOffset: currentOffset + Int64(i) * Int64(estimatedBytesPerPacket),
                        mVariableFramesInPacket: 0,
                        mDataByteSize: estimatedBytesPerPacket
                    )
                    self.packetDescriptions.append(desc)
                }
            }
        }

        // Decode all available packets into PCM buffers.
        // Check the cancellation flag each iteration so reset() can interrupt a large backlog
        // without waiting for every packet to be converted (which can take 10+ seconds after
        // a network stall clears and a burst of data arrives at once).
        while self.packetDescriptions.count >= 4 {
            if _isCancelled.withLock({ $0 }) {
                Log(.info, category: .playback, "MP3StreamDecoder[\(instanceID)] conversion loop cancelled with \(self.packetDescriptions.count) packets remaining")
                break
            }
            let pendingPacketsBeforeConversion = self.packetDescriptions.count
            convertToPCM()
            guard self.packetDescriptions.count < pendingPacketsBeforeConversion else {
                // `convertToPCM()` has early returns that consume nothing — a nil
                // converter, a failed PCM buffer allocation, a conversion that reports
                // noErr having taken zero packets — and none of them change this loop's
                // condition. Without this check the loop spins the serial decoder queue at
                // 100% until `reset()` flips the cancellation flag, while every queued
                // `decode(data:)` piles up behind it holding its own chunk (#1025).
                // Comparing the count across the call is robust to every no-progress path,
                // not only the ones we can enumerate today.
                Log(.debug, category: .playback, "MP3StreamDecoder[\(instanceID)] conversion consumed no packets (\(pendingPacketsBeforeConversion) queued, converter \(converter == nil ? "absent" : "present")); leaving the loop rather than spinning")
                break
            }
        }
    }

    /// Drops the undecoded backlog, and reports the drop on every surface that can carry
    /// it: the error stream, the log, and the shared ``ErrorReporter``.
    ///
    /// Reported rather than dropped quietly on purpose. #486 established that internal
    /// error paths in this subsystem are invisible in the field, and whether this cap ever
    /// fires — and how often — is precisely what shipping it is meant to find out.
    private func dropBacklog(incomingByteCount: Int) {
        overflowCount += 1

        let error = MP3DecoderError.backlogOverflow(
            droppedBytes: packetData.count,
            droppedPackets: packetDescriptions.count
        )
        Log(.error, category: .playback, "MP3StreamDecoder[\(instanceID)] dropping backlog: \(packetData.count) undecoded bytes / \(packetDescriptions.count) packets would exceed the \(Self.maxBufferedByteCount)-byte cap with a \(incomingByteCount)-byte callback (converter \(converter == nil ? "absent" : "present"), overflow #\(overflowCount))")
        errorContinuation.yield(error)
        ErrorReporting.shared.report(
            error,
            context: "MP3StreamDecoder handlePackets: undecoded backlog exceeded cap",
            category: .playback,
            additionalData: [
                "dropped_bytes": String(packetData.count),
                "dropped_packets": String(packetDescriptions.count),
                "incoming_bytes": String(incomingByteCount),
                "cap_bytes": String(Self.maxBufferedByteCount),
                "overflow_count": String(overflowCount),
                "has_converter": String(converter != nil),
            ]
        )

        packetData.removeAll(keepingCapacity: false)
        packetDescriptions.removeAll()
        consumedByteOffset = 0
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

        // Use withUnsafeBytes to avoid copying packetData into ConversionContext
        // The callback is invoked synchronously, so the pointer remains valid
        var ioOutputDataPacketSize = frameCapacity
        var status: OSStatus = noErr
        var consumedPackets = 0

        packetData.withUnsafeBytes { dataBuffer in
            guard let dataBaseAddress = dataBuffer.baseAddress else {
                status = kAudioConverterErr_InvalidInputSize
                return
            }

            // Create context with pointer to data - Deque uses copy-on-write so no actual copy occurs
            let context = ConversionContext(
                dataPointer: dataBaseAddress,
                dataCount: dataBuffer.count,
                packetDescriptions: packetDescriptions
            )
            let contextPointer = Unmanaged.passUnretained(context).toOpaque()

            status = AudioConverterFillComplexBuffer(
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

                    // Validate bounds carefully to avoid overflow
                    guard packetSize > 0,
                          packetOffset >= 0,
                          packetOffset < context.dataCount,
                          context.dataCount - packetOffset >= packetSize else {
                        ioNumberDataPackets.pointee = 0
                        return noErr
                    }

                    // Copy packet data to our buffer - source is already a pointer, no Data copy needed
                    let bufferPointer = context.getBuffer(capacity: packetSize)
                    memcpy(bufferPointer, context.dataPointer.advanced(by: packetOffset), packetSize)

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

            // Capture consumed packets before context goes out of scope
            consumedPackets = context.packetIndex
        }

        if status == noErr && ioOutputDataPacketSize > 0 {
            pcmBuffer.frameLength = ioOutputDataPacketSize

            // Track consumed packets without O(n) data removal
            if consumedPackets > 0 && consumedPackets <= packetDescriptions.count {
                // Find the end offset of consumed data
                let lastConsumedDesc = packetDescriptions[consumedPackets - 1]
                let consumedBytes = Int(lastConsumedDesc.mStartOffset + Int64(lastConsumedDesc.mDataByteSize))

                if consumedBytes > 0 && consumedBytes <= packetData.count {
                    // O(1): Just update the offset instead of O(n) removeFirst
                    consumedByteOffset = consumedBytes

                    // Remove consumed packet descriptions (O(n) on descriptions array, but it's small)
                    packetDescriptions.removeFirst(consumedPackets)

                    // Compact the data buffer periodically to avoid unbounded growth
                    if consumedByteOffset >= compactionThreshold {
                        compactDataBuffer()
                    }
                }
            }

            // Yield the decoded buffer
            bufferContinuation.yield(pcmBuffer)
        } else if status != noErr && status != kAudioConverterErr_InvalidInputSize {
            // Only clear on non-recoverable errors
            packetDescriptions.removeAll()
            packetData.removeAll()
            consumedByteOffset = 0
        }
    }

    /// Compacts the data buffer by removing consumed bytes.
    /// This is O(n) but only called periodically when consumedByteOffset exceeds threshold.
    private func compactDataBuffer() {
        guard consumedByteOffset > 0 else { return }

        // Remove the consumed bytes from the data buffer
        packetData.removeFirst(consumedByteOffset)

        // Adjust remaining packet descriptions to reflect the new base
        for i in 0..<packetDescriptions.count {
            packetDescriptions[i].mStartOffset -= Int64(consumedByteOffset)
        }

        consumedByteOffset = 0
    }

    // MARK: - Diagnostics

    /// A point-in-time view of the decoder's buffering state.
    ///
    /// One accessor rather than relaxing the individual stored properties, in the spirit
    /// of `AudioPlayerController.debugStateSnapshot`.
    struct BufferState: Sendable, Equatable {
        let bufferedByteCount: Int
        let pendingPacketCount: Int
        let consumedByteOffset: Int
        let hasConverter: Bool
        let overflowCount: Int
    }

    /// Reads ``BufferState`` on the decoder queue.
    ///
    /// Synchronous, so it waits for whatever the queue is already running. Callers must
    /// not read it while a `handlePackets()` call they know cannot return is outstanding.
    var bufferState: BufferState {
        decoderQueue.sync {
            BufferState(
                bufferedByteCount: packetData.count,
                pendingPacketCount: packetDescriptions.count,
                consumedByteOffset: consumedByteOffset,
                hasConverter: converter != nil,
                overflowCount: overflowCount
            )
        }
    }

    /// Delivers one synthetic packet callback on the decoder queue, exactly as the
    /// `AudioFileStream` packet callback does, and invokes `completion` once
    /// `handlePackets()` returns.
    ///
    /// A test seam. `handlePackets()` is otherwise reachable only through the C callback
    /// `AudioFileStreamParseBytes` fires while parsing real MP3 bytes, which always ends
    /// up with a converter — so the degenerate states this method exists to exercise (no
    /// converter, or a converter that consumes nothing) are unreachable from the public
    /// API even though the field hits them.
    ///
    /// `completion` is a callback rather than an `async` return deliberately: a caller
    /// needs to impose its own deadline on a `handlePackets()` that fails to return, and a
    /// child task suspended on a continuation the decoder queue will never resume cannot
    /// be cancelled back out of a task group.
    func deliverSyntheticPackets(
        bytes: Data,
        packetCount: UInt32,
        completion: @escaping @Sendable () -> Void
    ) {
        decoderQueue.async { [self] in
            bytes.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return }
                handlePackets(
                    numberBytes: UInt32(bytes.count),
                    numberPackets: packetCount,
                    inputData: baseAddress,
                    packetDescriptions: nil
                )
            }
            completion()
        }
    }
}

// MARK: - Supporting Types

/// Context for the audio converter callback.
/// Uses a raw pointer to avoid copying the packet data buffer.
/// Accepts a Deque directly to avoid O(n) Array copy - Deque uses copy-on-write
/// so no actual copy occurs since we don't mutate it.
private final class ConversionContext {
    /// Pointer to the packet data buffer (valid only during conversion)
    let dataPointer: UnsafeRawPointer
    /// Size of the data buffer
    let dataCount: Int
    /// Packet descriptions for the current conversion (Deque uses CoW, no copy if not mutated)
    let packetDescriptions: Deque<AudioStreamPacketDescription>
    /// Current packet index being processed
    var packetIndex: Int = 0

    /// Storage for current packet description - must remain valid between callback invocations
    private var packetDescriptionStorage: UnsafeMutablePointer<AudioStreamPacketDescription>

    /// Reusable buffer for packet data copy
    private var buffer: UnsafeMutablePointer<UInt8>?
    private var bufferCapacity: Int = 0

    init(dataPointer: UnsafeRawPointer, dataCount: Int, packetDescriptions: Deque<AudioStreamPacketDescription>) {
        self.dataPointer = dataPointer
        self.dataCount = dataCount
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
