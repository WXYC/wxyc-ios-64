//
//  MP3StreamDecoderBufferCapTests.swift
//  Playback
//
//  Tests that the MP3 decoder's undecoded packet backlog stays bounded, and that its
//  conversion loop always terminates, when nothing drains it. See issue #1025.
//
//  Created by Jake Bromberg on 08/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import MP3StreamerModule

#if !os(watchOS)

/// Covers the two unbounded paths in `MP3StreamDecoder.handlePackets()` that produced
/// Sentry IOS-6P: a `packetData` buffer with no ceiling, and a conversion loop whose exit
/// condition depends on work that several early returns decline to do.
///
/// These need no converter and no real MP3 bytes, so unlike `MP3StreamDecoderTests` they
/// are not gated behind `RUN_E2E` — the whole point is the state a real stream cannot
/// reach on demand.
@Suite("MP3StreamDecoder backlog bounds")
struct MP3StreamDecoderBufferCapTests {

    @Test("Backlog stays under the cap across many callbacks with no converter")
    func backlogStaysUnderCapAcrossManyCallbacks() async {
        let decoder = MP3StreamDecoder()

        // 256 callbacks of 64 KB — 16 MB in total, four packets each — is the shape of a
        // live stream (the HTTP layer delivers 16-64 KB chunks) whose converter was never
        // created. That is the state that reached a 896 MB allocation in #1025.
        let finished = await feed(decoder, callbacks: 256, byteCount: 64 * 1024, packetCount: 4)
        #expect(finished, "handlePackets() never returned: the conversion loop spun without consuming (#1025, defect 2)")
        guard finished else {
            decoder.reset()
            return
        }

        let state = decoder.bufferState
        #expect(!state.hasConverter, "Precondition: this decoder must have no converter, or nothing here is under test")
        #expect(
            state.bufferedByteCount <= MP3StreamDecoder.maxBufferedByteCount,
            "Undecoded backlog reached \(state.bufferedByteCount) bytes, above the \(MP3StreamDecoder.maxBufferedByteCount)-byte cap"
        )
        #expect(state.overflowCount > 0, "Feeding 16 MB with nothing draining it must trip the cap at least once")
    }

    @Test("Backlog is capped before the packet count reaches the conversion threshold")
    func backlogIsCappedBeforeConversionLoopEngages() async {
        let decoder = MP3StreamDecoder()

        // Three callbacks of 2 MB carrying one packet each. Deliberately fewer than the
        // four packet descriptions `handlePackets()` needs before it enters its conversion
        // loop: that isolates the missing cap (defect 1) from the loop's missing
        // forward-progress guarantee (defect 2), so an uncapped decoder fails the size
        // assertion below instead of hanging on the spin and never reaching it.
        let finished = await feed(decoder, callbacks: 3, byteCount: 2 * 1024 * 1024, packetCount: 1)
        #expect(finished, "handlePackets() should return promptly with fewer than four packets queued")
        guard finished else {
            decoder.reset()
            return
        }

        let state = decoder.bufferState
        #expect(state.pendingPacketCount < 4, "Precondition: the conversion loop must not have engaged, or this is testing defect 2")
        #expect(
            state.bufferedByteCount <= MP3StreamDecoder.maxBufferedByteCount,
            "Undecoded backlog reached \(state.bufferedByteCount) bytes, above the \(MP3StreamDecoder.maxBufferedByteCount)-byte cap"
        )
    }

    @Test("The conversion loop returns when conversion consumes nothing")
    func conversionLoopReturnsWhenNothingIsConsumed() async {
        let decoder = MP3StreamDecoder()

        // Eight packet descriptions clears the loop's `>= 4` entry condition. With no
        // converter, `convertToPCM()` returns at its first guard without consuming any of
        // them, so the loop condition never changes and only a forward-progress check can
        // end it.
        let finished = await feed(decoder, callbacks: 1, byteCount: 16 * 1024, packetCount: 8)
        #expect(finished, "handlePackets() never returned: with nothing consumed the loop condition never changes (#1025, defect 2)")
        if !finished {
            decoder.reset()
        }
    }

    @Test("Dropping the backlog yields a distinct, observable error")
    func overflowYieldsDistinctError() async {
        let decoder = MP3StreamDecoder()

        let finished = await feed(decoder, callbacks: 3, byteCount: 2 * 1024 * 1024, packetCount: 1)
        guard finished else {
            decoder.reset()
            Issue.record("handlePackets() never returned, so the error stream could not be observed")
            return
        }

        switch await firstError(from: decoder, timeout: .seconds(5)) {
        case let .backlogOverflow(droppedBytes, droppedPackets):
            #expect(droppedBytes > 0, "The dropped byte count is the whole point of the report")
            #expect(droppedPackets > 0, "A dropped backlog carries the packet descriptions with it")
        case let .other(description):
            Issue.record("Expected MP3DecoderError.backlogOverflow, got \(description)")
        case .none:
            Issue.record("Overflowing the backlog must not fail silently — no error reached errorStream (#486)")
        }
    }
}

// MARK: - Test Support

/// What the decoder reported on `errorStream`, reduced to something `Sendable` so it can
/// cross a task-group boundary (`any Error` cannot).
private enum ObservedDecoderError: Sendable {
    case backlogOverflow(droppedBytes: Int, droppedPackets: Int)
    case other(String)
    case none
}

/// Delivers `callbacks` synthetic packet callbacks and waits for the last one to return.
///
/// Returns `false` when `timeout` elapses first. The deadline is the point: before the
/// forward-progress guard, `handlePackets()` can spin the decoder queue forever, and the
/// spin checks nothing a test can signal short of `reset()`. A `.timeLimit` trait cannot
/// rescue the suite from that, because the hang is on a `DispatchQueue` rather than in a
/// cancellable task — so the test owns its deadline and fails on it instead of hanging.
private func feed(
    _ decoder: MP3StreamDecoder,
    callbacks: Int,
    byteCount: Int,
    packetCount: UInt32,
    timeout: Duration = .seconds(10)
) async -> Bool {
    let (completions, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .unbounded)
    let payload = Data(repeating: 0xAA, count: byteCount)

    for index in 0..<callbacks {
        let isLast = index == callbacks - 1
        decoder.deliverSyntheticPackets(bytes: payload, packetCount: packetCount) {
            guard isLast else { return }
            continuation.yield()
            continuation.finish()
        }
    }

    return await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            for await _ in completions {
                return true
            }
            return false
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return false
        }
        let finished = await group.next() ?? false
        group.cancelAll()
        return finished
    }
}

/// Reads the first value off the decoder's error stream, or gives up after `timeout`.
private func firstError(from decoder: MP3StreamDecoder, timeout: Duration) async -> ObservedDecoderError {
    await withTaskGroup(of: ObservedDecoderError.self) { group in
        group.addTask {
            for await error in decoder.errorStream {
                if case let MP3DecoderError.backlogOverflow(droppedBytes, droppedPackets) = error {
                    return .backlogOverflow(droppedBytes: droppedBytes, droppedPackets: droppedPackets)
                }
                return .other(String(describing: error))
            }
            return .none
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return .none
        }
        let observed = await group.next() ?? .none
        group.cancelAll()
        return observed
    }
}

#endif // !os(watchOS)
