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
        guard await feedOrFail(
            decoder,
            callbacks: 256,
            byteCount: 64 * 1024,
            packetCount: 4,
            hangMessage: "handlePackets() never returned: the conversion loop spun without consuming (#1025, defect 2)"
        ) else { return }

        let state = decoder.bufferState
        #expect(!state.hasConverter, "Precondition: this decoder must have no converter, or nothing here is under test")
        #expect(
            state.bufferedByteCount <= MP3StreamDecoder.maxBufferedByteCount,
            "Undecoded backlog reached \(state.bufferedByteCount) bytes, above the \(MP3StreamDecoder.maxBufferedByteCount)-byte cap"
        )
        #expect(state.overflowCount > 0, "Feeding 16 MB with nothing draining it must trip the cap at least once")
        // The cap's contract is per callback, not per session, and `bufferedByteCount` is
        // one terminal sample: a decoder that ran over the ceiling in the middle and
        // happened to be under it at the end reads as compliant. The high-water mark is
        // what actually pins "after handlePackets returns, always".
        #expect(
            state.peakBufferedByteCount <= MP3StreamDecoder.maxBufferedByteCount,
            "Undecoded backlog peaked at \(state.peakBufferedByteCount) bytes, above the \(MP3StreamDecoder.maxBufferedByteCount)-byte cap, even though it ended at \(state.bufferedByteCount)"
        )
        #expect(
            state.noProgressBreakCount > 1,
            "The forward-progress guard is taken once per packet callback for as long as the decoder stays stuck, so anything it does per break — logging above all — is on an unbounded hot path"
        )
    }

    @Test("Backlog is capped before the packet count reaches the conversion threshold")
    func backlogIsCappedBeforeConversionLoopEngages() async {
        let decoder = MP3StreamDecoder()

        // Three callbacks of 2 MB carrying one packet each. Deliberately fewer than the
        // four packet descriptions `handlePackets()` needs before it enters its conversion
        // loop: that isolates the missing cap (defect 1) from the loop's missing
        // forward-progress guarantee (defect 2), so an uncapped decoder fails the size
        // assertion below instead of hanging on the spin and never reaching it.
        guard await feedOrFail(
            decoder,
            callbacks: 3,
            byteCount: 2 * 1024 * 1024,
            packetCount: 1,
            hangMessage: "handlePackets() should return promptly with fewer than four packets queued"
        ) else { return }

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
        _ = await feedOrFail(
            decoder,
            callbacks: 1,
            byteCount: 16 * 1024,
            packetCount: 8,
            hangMessage: "handlePackets() never returned: with nothing consumed the loop condition never changes (#1025, defect 2)"
        )
    }

    @Test("Dropping the backlog yields a distinct, observable error")
    func overflowYieldsDistinctError() async {
        let decoder = MP3StreamDecoder()

        guard await feedOrFail(
            decoder,
            callbacks: 3,
            byteCount: 2 * 1024 * 1024,
            packetCount: 1,
            hangMessage: "handlePackets() never returned, so the error stream could not be observed"
        ) else { return }

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

    @Test("A callback larger than the whole cap is reported as dropped, not as a zero-byte drop")
    func overflowReportsTheDiscardedCallbackToo() async {
        let decoder = MP3StreamDecoder()

        // One callback a byte over the cap, against an empty buffer. `handlePackets()`
        // cannot buffer it even with nothing in the way, so it discards the callback on top
        // of the (here empty) backlog — which makes this the largest single loss the cap
        // ever causes, and the one its report described least: the backlog alone was zero.
        let oversizedByteCount = MP3StreamDecoder.maxBufferedByteCount + 1
        guard await feedOrFail(
            decoder,
            callbacks: 1,
            byteCount: oversizedByteCount,
            packetCount: 4,
            hangMessage: "handlePackets() never returned on an oversized callback"
        ) else { return }

        switch await firstError(from: decoder, timeout: .seconds(5)) {
        case let .backlogOverflow(droppedBytes, droppedPackets):
            #expect(
                droppedBytes == oversizedByteCount,
                "The discarded callback is the loss here; reporting \(droppedBytes) bytes names only the empty backlog"
            )
            #expect(
                droppedPackets == 4,
                "The discarded callback's packets went with it; reporting \(droppedPackets) names only the empty backlog"
            )
        case let .other(description):
            Issue.record("Expected MP3DecoderError.backlogOverflow, got \(description)")
        case .none:
            Issue.record("Discarding an oversized callback must not fail silently (#486)")
        }
    }

    @Test("A decoder that keeps overflowing throttles its reports without losing the first")
    func repeatedOverflowsAreThrottled() async {
        let decoder = MP3StreamDecoder()

        // 1024 callbacks of 64 KB — 64 MB, about an hour of the 128 kbps stream. A stuck
        // decoder re-trips the cap once per 4 MB, so this is roughly what a listener who
        // leaves a broken stream running in the background produces. Unthrottled, every one
        // of those is an identical event to Sentry and to PostHog.
        guard await feedOrFail(
            decoder,
            callbacks: 1024,
            byteCount: 64 * 1024,
            packetCount: 4,
            hangMessage: "handlePackets() never returned while overflowing repeatedly"
        ) else { return }

        let state = decoder.bufferState
        #expect(
            state.overflowCount > 8,
            "Precondition: the feed must trip the cap often enough for throttling to be observable, got \(state.overflowCount)"
        )
        #expect(
            state.reportedOverflowCount >= 1,
            "The first overflow must always be reported — whether this cap ever fires in the field is the reason it ships"
        )
        #expect(
            state.reportedOverflowCount < state.overflowCount,
            "\(state.overflowCount) overflows produced \(state.reportedOverflowCount) reports; an unthrottled decoder sends one per overflow"
        )
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

/// Runs `work` under a deadline, substituting `fallback` if the deadline wins.
///
/// Every wait in this file needs its own deadline rather than a `.timeLimit` trait: the
/// hang under test is on a `DispatchQueue`, not in a cancellable task, so cancellation
/// cannot reach it and the suite would hang instead of failing. Written once so the two
/// callers cannot drift apart on the race itself.
func withDeadline<Result: Sendable>(
    _ timeout: Duration,
    fallback: Result,
    _ work: @escaping @Sendable () async -> Result
) async -> Result {
    await withTaskGroup(of: Result.self) { group in
        group.addTask { await work() }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return fallback
        }
        let result = await group.next() ?? fallback
        group.cancelAll()
        return result
    }
}

/// Delivers `callbacks` synthetic packet callbacks and waits for the last one to return.
///
/// Returns `false` when `timeout` elapses first — which, before the forward-progress
/// guard, is what a `handlePackets()` spinning the decoder queue looks like from here.
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

    return await withDeadline(timeout, fallback: false) {
        for await _ in completions {
            return true
        }
        return false
    }
}

/// ``feed(_:callbacks:byteCount:packetCount:timeout:)``, reporting the hang itself.
///
/// Every test here has the same two obligations when the decoder fails to return — record
/// why, and `reset()` so the spinning queue does not outlive the test — and had drifted
/// into four slightly different spellings of them.
@discardableResult
private func feedOrFail(
    _ decoder: MP3StreamDecoder,
    callbacks: Int,
    byteCount: Int,
    packetCount: UInt32,
    hangMessage: Comment,
    sourceLocation: SourceLocation = #_sourceLocation
) async -> Bool {
    let finished = await feed(decoder, callbacks: callbacks, byteCount: byteCount, packetCount: packetCount)
    if !finished {
        decoder.reset()
        Issue.record(hangMessage, sourceLocation: sourceLocation)
    }
    return finished
}

/// Reads the first value off the decoder's error stream, or gives up after `timeout`.
private func firstError(from decoder: MP3StreamDecoder, timeout: Duration) async -> ObservedDecoderError {
    await withDeadline(timeout, fallback: .none) {
        for await error in decoder.errorStream {
            if case let MP3DecoderError.backlogOverflow(droppedBytes, droppedPackets) = error {
                return .backlogOverflow(droppedBytes: droppedBytes, droppedPackets: droppedPackets)
            }
            return .other(String(describing: error))
        }
        return .none
    }
}

#endif // !os(watchOS)
