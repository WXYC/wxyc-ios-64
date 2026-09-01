//
//  MP3StreamerDecoderErrorForwardingTests.swift
//  Playback
//
//  Tests for the decoder-failure signal path: `MP3StreamDecoder` yields on
//  `errorStream`, `MP3Streamer` consumes it and forwards to the controller as an
//  `.error` internal event, throttled per failure kind. Before issue #1036 that
//  stream had no consumer at all, so `audioFileStreamError`,
//  `converterCreationFailed` and `bufferAllocationFailed` were silent in the
//  field — no Sentry event, no PostHog event, no `StreamErrorEvent`.
//
//  Companion to `MP3StreamerErrorEventTests`, which covers the streamer's own
//  failure paths (#486); this file covers the decoder's, which that issue did
//  not reach.
//
//  Created by Jake Bromberg on 08/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import PlaybackTestUtilities
import Foundation
import AVFoundation
import Core
import Logger
@testable import MP3StreamerModule
@testable import PlaybackCore

#if !os(watchOS)

@Suite("MP3Streamer Decoder Error Forwarding")
@MainActor
struct MP3StreamerDecoderErrorForwardingTests {
    static let testStreamURL = URL(string: "https://audio-mp3.ibiblio.org/wxyc.mp3")!

    /// Collects `.error` events off the streamer's internal event stream.
    private final class ErrorCollector {
        var errors: [Error] = []
        var decoderErrors: [MP3DecoderError] { errors.compactMap { $0 as? MP3DecoderError } }
    }

    private func makeStreamer() -> MP3Streamer {
        MP3Streamer(
            configuration: MP3StreamerConfiguration(
                url: Self.testStreamURL,
                minimumBuffersBeforePlayback: 2,
                startupTimeout: 5.0
            ),
            httpClient: MockHTTPStreamClient(),
            audioPlayer: MockAudioEnginePlayer()
        )
    }

    private func makeDrain(_ streamer: MP3Streamer, into collector: ErrorCollector) -> Task<Void, Never> {
        Task { @MainActor in
            for await event in streamer.eventStreamInternal {
                if case .error(let error) = event {
                    collector.errors.append(error)
                }
            }
        }
    }

    /// Polls until `condition` holds or the budget elapses. The forwarding path crosses
    /// the decoder queue and two task hops, so an unconditional sleep would either be
    /// flaky or needlessly slow.
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - Acceptance criterion 1: each silent failure reaches the analytics layer

    /// The three failures that were silent in the field before #1036. Each must reach the
    /// controller as an `.error` internal event, which is what `AudioPlayerController`
    /// turns into a `StreamErrorEvent`.
    @Test(
        "Each formerly silent decoder failure reaches the analytics layer",
        arguments: [
            MP3DecoderError.audioFileStreamError(-50),
            MP3DecoderError.converterCreationFailed(-50),
            MP3DecoderError.bufferAllocationFailed
        ]
    )
    func forwardsFormerlySilentDecoderFailures(error: MP3DecoderError) async throws {
        let streamer = makeStreamer()
        let collector = ErrorCollector()
        let drain = makeDrain(streamer, into: collector)
        defer { drain.cancel() }

        streamer.deliverSyntheticDecoderError(error)

        let arrived = await waitUntil { !collector.decoderErrors.isEmpty }
        #expect(arrived, "\(error.kind.rawValue) never reached the analytics layer")
        #expect(collector.decoderErrors.first?.kind == error.kind)
    }

    // MARK: - Acceptance criterion 2: repeats do not emit one event per occurrence

    /// `bufferAllocationFailed` is raised inside `convertToPCM()`, once per packet
    /// callback, so an unthrottled forward would emit one analytics event per failed
    /// conversion for the life of the session. Sixteen occurrences must forward the 1st,
    /// 2nd, 4th, 8th and 16th — five events, not sixteen.
    @Test("Repeated failures of one kind are throttled geometrically")
    func repeatedFailuresAreThrottled() async throws {
        let streamer = makeStreamer()
        let collector = ErrorCollector()
        let drain = makeDrain(streamer, into: collector)
        defer { drain.cancel() }

        // Paced deliberately. `errorStream` is `.bufferingNewest(4)`, so a burst of 16
        // back-to-back yields is DROPPED down to whatever the consumer manages to pick
        // up — the throttle would then be counting an arbitrary subset and the assertion
        // below would be timing-dependent. Pacing lets all 16 occurrences actually reach
        // the consumer, which is what makes the expected series exact. Do not collapse
        // this back into a tight loop.
        for _ in 0..<16 {
            streamer.deliverSyntheticDecoderError(.bufferAllocationFailed)
            try await Task.sleep(for: .milliseconds(10))
        }

        try await Task.sleep(for: .milliseconds(300))

        #expect(
            collector.decoderErrors.count == 5,
            "16 occurrences should forward 5 events (1st, 2nd, 4th, 8th, 16th), got \(collector.decoderErrors.count)"
        )
    }

    /// The throttle is keyed per kind, so a flood of one failure cannot suppress the first
    /// occurrence of a different one — the case where the second failure is the
    /// interesting one.
    @Test("A flood of one kind does not mask the first occurrence of another")
    func throttleIsPerKind() async throws {
        let streamer = makeStreamer()
        let collector = ErrorCollector()
        let drain = makeDrain(streamer, into: collector)
        defer { drain.cancel() }

        for _ in 0..<8 {
            streamer.deliverSyntheticDecoderError(.bufferAllocationFailed)
        }
        streamer.deliverSyntheticDecoderError(.converterCreationFailed(-50))

        let sawConverter = await waitUntil {
            collector.decoderErrors.contains { $0.kind == .converterCreationFailed }
        }
        #expect(sawConverter, "converterCreationFailed was masked by the bufferAllocationFailed flood")
    }

    // MARK: - Acceptance criterion 4: backlogOverflow uses exactly one channel

    /// `backlogOverflow` reports itself to `ErrorReporting.shared` on a geometric throttle
    /// of its own (#1030). Forwarding it here as well would report one occurrence through
    /// two channels — and re-introduce, per occurrence, the flood that throttle exists to
    /// bound. It is also not a playback failure: the decoder drops a backlog and keeps
    /// running.
    @Test("backlogOverflow is not forwarded to the analytics layer")
    func backlogOverflowIsNotForwarded() async throws {
        let streamer = makeStreamer()
        let collector = ErrorCollector()
        let drain = makeDrain(streamer, into: collector)
        defer { drain.cancel() }

        streamer.deliverSyntheticDecoderError(
            .backlogOverflow(droppedBytes: 4_194_304, droppedPackets: 512)
        )
        // A forwarded error of a different kind, delivered after it, proves the consumer
        // was alive and reading the whole time — without this the assertion below would
        // also pass if the consumer were simply broken.
        streamer.deliverSyntheticDecoderError(.bufferAllocationFailed)

        let sawProbe = await waitUntil {
            collector.decoderErrors.contains { $0.kind == .bufferAllocationFailed }
        }
        #expect(sawProbe, "consumer was not running; the overflow assertion would be vacuous")
        #expect(
            !collector.decoderErrors.contains { $0.kind == .backlogOverflow },
            "backlogOverflow reached the analytics layer as well as ErrorReporting — counted twice"
        )
    }

    // MARK: - Error descriptions

    /// `StreamErrorEvent` has no free-form context dictionary, so `error_description` is
    /// the only field that can say which decoder failure fired and what the underlying
    /// API returned. Without `LocalizedError` these bridge to a case *ordinal*.
    @Test("Decoder errors describe themselves legibly")
    func decoderErrorsAreLegible() throws {
        let converter = MP3DecoderError.converterCreationFailed(-50).localizedDescription
        #expect(converter.contains("converter"))
        #expect(converter.contains("-50"), "the OSStatus must survive into the description")

        let stream = MP3DecoderError.audioFileStreamError(-39).localizedDescription
        #expect(stream.contains("AudioFileStream"))
        #expect(stream.contains("-39"))

        let buffer = MP3DecoderError.bufferAllocationFailed.localizedDescription
        #expect(buffer.contains("buffer"))

        // The Foundation fallback for a bare Swift error. Its presence would mean the
        // conformance is not being used and the events are ordinals again.
        #expect(!converter.contains("The operation couldn"))
    }
}

/// The two decoder paths that failed with no signal at all before #1036 — not even a
/// yield nothing was reading. They are covered here at the decoder level: the forwarding
/// from `errorStream` to the analytics layer is already proven by the suite above, so
/// showing the site yields completes the chain.
@Suite("MP3StreamDecoder Silent Failure Paths")
struct MP3StreamDecoderSilentPathTests {

    /// Drains `errorStream` into a `Sendable` box.
    private actor Collector {
        var errors: [MP3DecoderError] = []
        func append(_ error: Error) {
            if let decoderError = error as? MP3DecoderError { errors.append(decoderError) }
        }
        var kinds: [MP3DecoderError.Kind] { errors.map(\.kind) }
    }

    private func drain(_ decoder: MP3StreamDecoder, into collector: Collector) -> Task<Void, Never> {
        Task { for await error in decoder.errorStream { await collector.append(error) } }
    }

    private func waitForKind(
        _ kind: MP3DecoderError.Kind,
        in collector: Collector,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await collector.kinds.contains(kind) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await collector.kinds.contains(kind)
    }

    /// `handlePropertyChange` used to `return` silently when `AudioFileStreamGetProperty`
    /// failed, leaving `converter` nil for the life of the decoder — the #1025 state,
    /// reached with no signal of any kind. Driving the property callback against a stream
    /// that has been opened but has not parsed a frame header reproduces exactly that.
    @Test("A failed AudioFileStreamGetProperty is reported")
    func propertyReadFailureIsReported() async throws {
        let decoder = MP3StreamDecoder()
        let collector = Collector()
        let drainTask = drain(decoder, into: collector)
        defer { drainTask.cancel() }

        // Opens the AudioFileStream without giving it a parseable data format.
        decoder.decode(data: Data(repeating: 0x00, count: 64))

        let done = SendableBox()
        decoder.deliverSyntheticPropertyChange { done.signal() }
        _ = await done.wait()

        #expect(
            await waitForKind(.audioFileStreamError, in: collector),
            "a failed data-format read produced no error — the path is silent again"
        )
    }

    /// The fatal-parse-status branch used to be an `if` body containing only a comment.
    /// Whether AudioToolbox actually returns a fatal status for a given garbage payload is
    /// its business, so this test asserts the weaker true thing: feeding unparseable bytes
    /// must not *crash or hang*, and if a fatal status does arise it must now surface
    /// rather than vanish. The `:319` test above is the deterministic one.
    @Test("Unparseable bytes never fail silently in a way that hangs the decoder")
    func garbageBytesDoNotHang() async throws {
        let decoder = MP3StreamDecoder()
        let collector = Collector()
        let drainTask = drain(decoder, into: collector)
        defer { drainTask.cancel() }

        decoder.decode(data: Data(repeating: 0xFF, count: 8192))
        try await Task.sleep(for: .milliseconds(300))

        // Whatever AudioToolbox decided, the decoder is still responsive and any error it
        // did raise is an MP3DecoderError rather than a swallowed status.
        let kinds = await collector.kinds
        #expect(kinds.allSatisfy { $0 == .audioFileStreamError || $0 == .converterCreationFailed })
    }
}

/// One-shot completion latch for the callback-style decoder seams.
private final class SendableBox: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    func signal() { semaphore.signal() }
    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                _ = self.semaphore.wait(timeout: .now() + 5)
                continuation.resume(returning: true)
            }
        }
    }
}

#endif // !os(watchOS)
