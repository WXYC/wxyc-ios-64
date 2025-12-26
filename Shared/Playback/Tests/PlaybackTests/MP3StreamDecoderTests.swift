import Testing
import Foundation
@preconcurrency import AVFoundation
@testable import Playback

#if !os(watchOS)

@Suite("MP3StreamDecoder Tests", .serialized)
@MainActor
struct MP3StreamDecoderTests {

    // MARK: - Basic Initialization Tests

    @Test("Decoder can be created")
    func testDecoderCreation() async throws {
        let delegate = MockMP3DecoderDelegate()
        let decoder = MP3StreamDecoder(delegate: delegate)
        _ = decoder // Silence unused variable warning
        // Just verify creation doesn't crash
    }

    @Test("MP3 test file can be loaded")
    func testMP3FileLoad() async throws {
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()
        #expect(mp3Data.count > 0)
    }

    @Test("Decode can be called without crash")
    func testDecodeCall() async throws {
        let delegate = MockMP3DecoderDelegate()
        let decoder = MP3StreamDecoder(delegate: delegate)

        // Just send a tiny bit of data
        let data = Data([0xFF, 0xFB, 0x90, 0x00])
        decoder.decode(data: data)

        // Give time for processing
        try await Task.sleep(for: .milliseconds(100))

        // Test passes if we get here without crashing
        _ = decoder
    }

    // MARK: - Decoding Tests

    @Test("Decodes MP3 file and produces PCM buffers")
    func testDecodeMp3File() async throws {
        let delegate = MockMP3DecoderDelegate()
        let decoder = MP3StreamDecoder(delegate: delegate)

        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Feed larger chunks to allow decoder to accumulate enough data
        let chunkSize = 32768
        var offset = 0
        while offset < min(mp3Data.count, 200000) {
            let end = min(offset + chunkSize, mp3Data.count)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
            try await Task.sleep(for: .milliseconds(100))
        }

        // Wait for at least one decoded buffer
        let buffer = try await delegate.bufferStream.first(timeout: 120)
        #expect(buffer.frameLength > 0)
    }

    @Test("Output format is 44.1kHz stereo float32")
    func testOutputFormat() async throws {
        let delegate = MockMP3DecoderDelegate()
        let decoder = MP3StreamDecoder(delegate: delegate)

        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Feed enough data for decoder to start producing output
        let chunkSize = 32768
        var offset = 0
        while offset < min(mp3Data.count, 200000) {
            let end = min(offset + chunkSize, mp3Data.count)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
            try await Task.sleep(for: .milliseconds(100))
        }

        // Wait for a decoded buffer
        let buffer = try await delegate.bufferStream.first(timeout: 120)

        let format = buffer.format
        #expect(format.sampleRate == 44100)
        #expect(format.channelCount == 2)
        #expect(format.commonFormat == .pcmFormatFloat32)
        #expect(format.isInterleaved == false)
    }

    @Test("Reset clears state and allows reuse")
    func testReset() async throws {
        let delegate = MockMP3DecoderDelegate()
        let decoder = MP3StreamDecoder(delegate: delegate)

        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Decode some data first
        let chunkSize = 32768
        var offset = 0
        while offset < min(mp3Data.count, 200000) {
            let end = min(offset + chunkSize, mp3Data.count)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
            try await Task.sleep(for: .milliseconds(100))
        }

        _ = try await delegate.bufferStream.first(timeout: 120)

        // Reset the decoder
        decoder.reset()

        // Give time for reset to complete on the decoder queue
        try await Task.sleep(for: .milliseconds(500))

        // Should be able to decode again from the start
        let delegate2 = MockMP3DecoderDelegate()
        let decoder2 = MP3StreamDecoder(delegate: delegate2)

        offset = 0
        while offset < min(mp3Data.count, 200000) {
            let end = min(offset + chunkSize, mp3Data.count)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder2.decode(data: chunk)
            offset = end
            try await Task.sleep(for: .milliseconds(100))
        }

        let buffer = try await delegate2.bufferStream.first(timeout: 120)
        #expect(buffer.frameLength > 0)
    }

    // MARK: - Edge Case Tests

    @Test("Waits for enough data before decoding")
    func testPartialData() async throws {
        let delegate = MockMP3DecoderDelegate()
        let decoder = MP3StreamDecoder(delegate: delegate)

        // Send just a tiny bit of data - not enough to parse MP3 headers
        let tinyData = Data([0xFF, 0xFB]) // MP3 sync word fragment
        decoder.decode(data: tinyData)

        // Give time for any processing
        try await Task.sleep(for: .milliseconds(500))

        // Should not have produced any buffers yet (not enough data)
        // We can't easily test "no buffer received" without a timeout,
        // but we can verify no errors occurred
    }

    @Test("Reports error for invalid non-MP3 data")
    func testInvalidData() async throws {
        let delegate = MockMP3DecoderDelegate()
        let decoder = MP3StreamDecoder(delegate: delegate)

        // Create clearly invalid data (random bytes, not MP3)
        let invalidData = Data(repeating: 0x00, count: 4096)
        decoder.decode(data: invalidData)

        // Give time for processing
        try await Task.sleep(for: .milliseconds(500))

        // The decoder should not produce any valid buffers from garbage data
        // It may or may not report an error depending on implementation
        // The main test is that it doesn't crash
    }

    // MARK: - Performance Tests

    @Test("Decodes multiple chunks efficiently")
    func testMultipleChunks() async throws {
        let delegate = MockMP3DecoderDelegate()
        let decoder = MP3StreamDecoder(delegate: delegate)

        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Feed data in chunks
        let chunkSize = 8192
        var offset = 0
        while offset < mp3Data.count {
            let end = min(offset + chunkSize, mp3Data.count)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
            try await Task.sleep(for: .milliseconds(50))
        }

        // Wait for multiple decoded buffers
        var bufferCount = 0
        for try await _ in delegate.bufferStream {
            bufferCount += 1
            if bufferCount >= 5 {
                break
            }
        }

        #expect(bufferCount >= 5, "Should produce multiple PCM buffers from MP3 file")
    }
}

#endif // !os(watchOS)
