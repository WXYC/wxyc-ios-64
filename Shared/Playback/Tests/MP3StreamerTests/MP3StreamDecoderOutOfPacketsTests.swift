//
//  MP3StreamDecoderOutOfPacketsTests.swift
//  Playback
//
//  Tests that MP3StreamDecoder keeps decoding after a conversion asks for more
//  packets than are queued, rather than ending its converter's stream (#1129).
//
//  Created by Jake Bromberg on 10/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
@preconcurrency import AVFoundation
@testable import MP3StreamerModule

#if !os(watchOS)

/// Covers the conversion that runs out of queued packets partway through an output buffer.
///
/// The conversion loop starts once four packets are queued, but the first conversion also
/// absorbs the decoder's priming frames and asks for a fifth. A first network chunk small
/// enough to queue exactly four therefore runs the input proc dry on the very first call.
/// Answering that with `noErr` tells `AudioConverter` the stream has ended: it emits two
/// buffers and nothing after them, which is the `buffering(2/5)` startup stall in #1129.
///
/// Unlike `MP3StreamDecoderTests` this suite is not gated behind `RUN_E2E`. It needs the
/// real converter — the defect lives in the contract with it — but it uses no sleeps and
/// finishes as soon as the buffers arrive, so it can afford to run in the default plan,
/// and a regression test nothing runs would guard nothing.
@Suite("MP3StreamDecoder running out of packets")
struct MP3StreamDecoderOutOfPacketsTests {
    /// What `MP3StreamerConfiguration.minimumBuffersBeforePlayback` defaults to: the
    /// number of buffers a stream must produce before playback can begin at all.
    static let buffersNeededToStartPlayback = 5

    /// Straddles the first-chunk sizes at which the fixture queues exactly four packets
    /// (4,704 to 6,784 bytes), with a healthy size on either side.
    @Test(
        "Keeps decoding when the first chunk queues too few packets for one output buffer",
        arguments: Array(stride(from: 4096, through: 7168, by: 512))
    )
    func keepsDecodingAfterRunningDry(firstChunkSize: Int) async throws {
        let mp3Data = try TestAudioBufferFactory.loadMP3TestData()
        let decoder = MP3StreamDecoder()

        decoder.decode(data: Data(mp3Data.prefix(firstChunkSize)))
        decoder.decode(data: Data(mp3Data.dropFirst(firstChunkSize)))

        let produced = await bufferCount(
            from: decoder.decodedBufferStream,
            upTo: Self.buffersNeededToStartPlayback,
            within: .seconds(5)
        )
        #expect(
            produced >= Self.buffersNeededToStartPlayback,
            "A \(firstChunkSize)-byte first chunk left the decoder at \(produced) buffers; the converter was told its stream had ended"
        )
    }

    /// Counts buffers until `limit` arrive or `timeout` elapses, whichever is first.
    private func bufferCount(
        from stream: AsyncStream<AVAudioPCMBuffer>,
        upTo limit: Int,
        within timeout: Duration
    ) async -> Int {
        await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                var count = 0
                for await _ in stream {
                    count += 1
                    if count >= limit { break }
                }
                return count
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            // Whichever child finishes first cancels the other. Cancelling the counter
            // ends its `for await`, so it still reports how far it got.
            var produced = 0
            for await count in group {
                if let count { produced = count }
                group.cancelAll()
            }
            return produced
        }
    }
}

#endif // !os(watchOS)
