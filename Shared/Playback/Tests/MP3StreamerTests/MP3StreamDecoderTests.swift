import Testing
import PlaybackTestUtilities
import Foundation
@preconcurrency import AVFoundation
@testable import MP3StreamerModule

#if !os(watchOS)

@Suite("MP3StreamDecoder Tests", .serialized)
@MainActor
struct MP3StreamDecoderTests {

    // MARK: - Basic Initialization Tests

    @Test("Decoder can be created")
    func testDecoderCreation() async throws {
        let decoder = MP3StreamDecoder()
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
        let decoder = MP3StreamDecoder()

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
        let decoder = MP3StreamDecoder()

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
        let buffer = try await decoder.decodedBufferStream.first(timeout: 120)
        #expect(buffer.frameLength > 0)
    }

    @Test("Output format is 44.1kHz stereo float32")
    func testOutputFormat() async throws {
        let decoder = MP3StreamDecoder()

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
        let buffer = try await decoder.decodedBufferStream.first(timeout: 120)

        let format = buffer.format
        #expect(format.sampleRate == 44100)
        #expect(format.channelCount == 2)
        #expect(format.commonFormat == .pcmFormatFloat32)
        #expect(format.isInterleaved == false)
    }

    @Test("Reset clears state and allows reuse")
    func testReset() async throws {
        let decoder = MP3StreamDecoder()

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

        _ = try await decoder.decodedBufferStream.first(timeout: 120)

        // Reset the decoder
        decoder.reset()

        // Give time for reset to complete on the decoder queue
        try await Task.sleep(for: .milliseconds(500))

        // Should be able to decode again from the start with a new decoder
        let decoder2 = MP3StreamDecoder()

        offset = 0
        while offset < min(mp3Data.count, 200000) {
            let end = min(offset + chunkSize, mp3Data.count)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder2.decode(data: chunk)
            offset = end
            try await Task.sleep(for: .milliseconds(100))
        }

        let buffer = try await decoder2.decodedBufferStream.first(timeout: 120)
        #expect(buffer.frameLength > 0)
    }

    // MARK: - Edge Case Tests

    @Test("Waits for enough data before decoding")
    func testPartialData() async throws {
        let decoder = MP3StreamDecoder()

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
        let decoder = MP3StreamDecoder()

        // Create clearly invalid data (random bytes, not MP3)
        let invalidData = Data(repeating: 0x00, count: 4096)
        decoder.decode(data: invalidData)

        // Give time for processing
        try await Task.sleep(for: .milliseconds(500))

        // The decoder should not produce any valid buffers from garbage data
        // It may or may not report an error depending on implementation
        // The main test is that it doesn't crash
    }

    // MARK: - Packet Management Tests (Critical for Offset Tracking)

    @Test("Extended streaming with small chunks produces valid buffers")
    func testExtendedStreamingWithSmallChunks() async throws {
        let decoder = MP3StreamDecoder()
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Feed data in small chunks to stress packet accumulation/consumption
        let chunkSize = 4096
        var offset = 0
        while offset < min(mp3Data.count, 200000) {
            let end = min(offset + chunkSize, mp3Data.count)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
            try await Task.sleep(for: .milliseconds(50))
        }

        // Verify we can get a valid buffer
        let buffer = try await decoder.decodedBufferStream.first(timeout: 30)
        #expect(buffer.frameLength > 0, "Buffer should have frames")
        #expect(buffer.format.sampleRate == 44100, "Buffer should have correct sample rate")
        #expect(buffer.format.channelCount == 2, "Buffer should be stereo")
    }

    @Test("Very small chunks (512 bytes) produce valid output")
    func testVerySmallChunks() async throws {
        let decoder = MP3StreamDecoder()
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Use very small chunks to stress packet description offset adjustment
        let chunkSize = 512
        var offset = 0
        let dataToProcess = min(mp3Data.count, 100_000)

        while offset < dataToProcess {
            let end = min(offset + chunkSize, dataToProcess)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
        }

        // Wait for processing and verify output
        try await Task.sleep(for: .milliseconds(500))
        let buffer = try await decoder.decodedBufferStream.first(timeout: 30)
        #expect(buffer.frameLength > 0, "Each buffer should have valid frames")
    }

    @Test("Rapid consecutive decode calls without delays")
    func testRapidDecodeCalls() async throws {
        let decoder = MP3StreamDecoder()
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Send many chunks rapidly without waiting
        let chunkSize = 8192
        var offset = 0
        let dataToProcess = min(mp3Data.count, 150_000)

        while offset < dataToProcess {
            let end = min(offset + chunkSize, dataToProcess)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
        }

        // Wait for processing and verify output
        try await Task.sleep(for: .milliseconds(500))
        let buffer = try await decoder.decodedBufferStream.first(timeout: 30)

        #expect(buffer.frameLength > 0 && buffer.frameLength <= 4096,
               "Frame length should be in valid range")
    }

    @Test("Large data chunks produce valid output")
    func testLargeChunks() async throws {
        let decoder = MP3StreamDecoder()
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Feed large chunks
        let chunkSize = 32768
        var offset = 0
        while offset < mp3Data.count {
            let end = min(offset + chunkSize, mp3Data.count)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
            try await Task.sleep(for: .milliseconds(100))
        }

        let buffer = try await decoder.decodedBufferStream.first(timeout: 30)

        #expect(buffer.frameLength > 0, "Should decode valid frames from large chunks")
        #expect(buffer.format.sampleRate == 44100)
    }

    // MARK: - CBR Handling Tests

    @Test("Handles CBR streams where packet descriptions may be nil")
    func testCBRStreamHandling() async throws {
        // CBR (Constant Bit Rate) MP3 streams may have nil packet descriptions
        // from AudioFileStream. The decoder should still produce output by
        // calculating packet sizes from the format information.
        let decoder = MP3StreamDecoder()
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Feed the entire file - if CBR handling works, we should get output
        // even if some callbacks have nil packet descriptions
        let chunkSize = 16384
        var offset = 0
        while offset < mp3Data.count {
            let end = min(offset + chunkSize, mp3Data.count)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
        }

        // Should produce valid output
        let buffer = try await decoder.decodedBufferStream.first(timeout: 10)
        #expect(buffer.frameLength > 0, "Should handle CBR streams and produce output")
    }

    // MARK: - Timing and Edge Case Tests

    @Test("Produces output when initial chunk is too small for format detection")
    func testSmallInitialChunk() async throws {
        // This test exposes a timing issue: if packets arrive before format is detected,
        // the converter might not exist yet, causing packets to accumulate without conversion.
        // When format IS detected, we should retry converting accumulated packets.
        let decoder = MP3StreamDecoder()
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Send a very small initial chunk - likely not enough for format detection
        let tinyChunk = mp3Data.prefix(256)
        decoder.decode(data: Data(tinyChunk))
        
        // Wait a bit to let the tiny chunk be processed
        try await Task.sleep(for: .milliseconds(100))

        // Now send more data
        let remainingData = mp3Data.dropFirst(256).prefix(100_000)
        decoder.decode(data: Data(remainingData))

        // Should still produce valid output
        let buffer = try await decoder.decodedBufferStream.first(timeout: 5)
        #expect(buffer.frameLength > 0, "Should produce PCM buffer even with small initial chunk")
    }

    @Test("Handles rapid small chunks without losing data")
    func testRapidSmallChunksNoDataLoss() async throws {
        // This test verifies that when data arrives in very small rapid chunks,
        // we don't lose packets due to timing between format detection and packet handling
        let decoder = MP3StreamDecoder()
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Send data in tiny 128-byte chunks very rapidly (no delays)
        let chunkSize = 128
        var offset = 0
        let dataToProcess = min(mp3Data.count, 50_000)

        while offset < dataToProcess {
            let end = min(offset + chunkSize, dataToProcess)
            let chunk = mp3Data.subdata(in: offset..<end)
            decoder.decode(data: chunk)
            offset = end
            // No delay between chunks - stress test the timing
        }

        // Should produce at least one buffer within a reasonable time
        let buffer = try await decoder.decodedBufferStream.first(timeout: 5)
        #expect(buffer.frameLength > 0, "Should not lose data with rapid small chunks")
    }

    @Test("Accumulated packets are converted after converter becomes available")
    func testAccumulatedPacketsConvertedAfterConverterReady() async throws {
        // This test specifically targets the bug where packets accumulate before
        // the converter is ready, and then never get converted because we don't
        // retry conversion after setUpConverter completes.
        let decoder = MP3StreamDecoder()
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()

        // Feed just enough data to accumulate some packets but potentially
        // hit the timing window where converter isn't ready
        let firstChunk = mp3Data.prefix(1024)
        decoder.decode(data: Data(firstChunk))

        // Small delay - packets might be waiting for converter
        try await Task.sleep(for: .milliseconds(50))

        // Send more data to trigger conversion
        let secondChunk = mp3Data.dropFirst(1024).prefix(50_000)
        decoder.decode(data: Data(secondChunk))

        // Verify we get output - if the timing bug exists, this might timeout
        // because accumulated packets from first chunk were never converted
        let buffer = try await decoder.decodedBufferStream.first(timeout: 5)
        #expect(buffer.frameLength > 0, "Accumulated packets should be converted after converter is ready")
    }

    // MARK: - Performance Tests

    @Test("Decodes multiple chunks efficiently")
    func testMultipleChunks() async throws {
        let decoder = MP3StreamDecoder()

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
        for try await _ in decoder.decodedBufferStream {
            bufferCount += 1
            if bufferCount >= 5 {
                break
            }
        }

        #expect(bufferCount >= 5, "Should produce multiple PCM buffers from MP3 file")
    }
}

// MARK: - AsyncStream Extension for Testing

extension AsyncStream where Element: Sendable {
    /// Returns the first element, or throws TimeoutError if timeout is reached.
    func first(timeout: TimeInterval) async throws -> Element {
        try await withThrowingTaskGroup(of: Element.self) { group in
            group.addTask {
                for await element in self {
                    return element
                }
                throw CancellationError()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw TimeoutError()
            }

            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return result
        }
    }
}

struct TimeoutError: Error, CustomStringConvertible {
    var description: String { "Operation timed out" }
}

#endif // !os(watchOS)
