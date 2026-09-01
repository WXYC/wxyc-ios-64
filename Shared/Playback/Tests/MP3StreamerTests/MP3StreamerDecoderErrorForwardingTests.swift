//
//  MP3StreamerDecoderErrorForwardingTests.swift
//  Playback
//
//  Tests for the decoder-failure signal path: `MP3StreamDecoder` yields on
//  `errorStream`, `MP3Streamer` consumes it and forwards to the controller as an
//  `.error` internal event, throttled per failure kind. Before issue #1036 that
//  stream had no consumer at all, so a failed `AudioFileStreamOpen`, a failed
//  converter creation and a failed PCM allocation were silent in the field — no
//  Sentry event, no PostHog event, no `StreamErrorEvent`.
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
import AudioToolbox
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

    // MARK: - Each formerly silent failure reaches the analytics layer

    @Test(
        "Each formerly silent decoder failure reaches the analytics layer",
        arguments: [
            MP3DecoderError.audioFileStreamOpenFailed(-50),
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

    // MARK: - Repeats do not emit one event per occurrence

    /// `bufferAllocationFailed` is raised inside `convertToPCM()`, once per packet
    /// callback, so an unthrottled forward would emit one analytics event per failed
    /// conversion for the life of the session. Sixteen occurrences forward the 1st, 2nd,
    /// 4th, 8th and 16th.
    @Test("Repeated failures of one kind are throttled geometrically")
    func repeatedFailuresAreThrottled() async throws {
        let streamer = makeStreamer()
        let collector = ErrorCollector()
        let drain = makeDrain(streamer, into: collector)
        defer { drain.cancel() }

        // Paced deliberately. `errorStream` is `.bufferingNewest(4)`, so a burst of 16
        // back-to-back yields is dropped down to whatever the consumer manages to pick up.
        // Pacing lets all 16 occurrences actually reach the consumer.
        for _ in 0..<16 {
            streamer.deliverSyntheticDecoderError(.bufferAllocationFailed)
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(300))

        // A range, not `== 5`, for the same reason the pacing exists: the channel is lossy,
        // and ~50ms of main-actor starvation is enough to drop one occurrence and land on 4
        // (1, 2, 4, 8) instead of 5. Either value falsifies "one event per occurrence",
        // which is the property under test; an exact count would just make load look like a
        // throttle regression.
        let count = collector.decoderErrors.count
        #expect(
            (4...5).contains(count),
            "16 occurrences should forward 4-5 events on a geometric throttle, got \(count)"
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

    /// The three `AudioFileStream` failures are separate kinds precisely so a parse-error
    /// flood — which repeats once per HTTP chunk, since nothing resets `audioFileStream`
    /// after a bad parse — cannot throttle away the property-read failure, which is the
    /// nil-converter signal (#1025) this issue most needs to surface.
    @Test("A parse-error flood does not mask a data-format failure")
    func parseFloodDoesNotMaskPropertyReadFailure() async throws {
        let streamer = makeStreamer()
        let collector = ErrorCollector()
        let drain = makeDrain(streamer, into: collector)
        defer { drain.cancel() }

        for _ in 0..<8 {
            streamer.deliverSyntheticDecoderError(.audioFileStreamParseFailed(-50))
        }
        streamer.deliverSyntheticDecoderError(.audioFileStreamPropertyReadFailed(-50))

        let sawPropertyRead = await waitUntil {
            collector.decoderErrors.contains { $0.kind == .audioFileStreamPropertyReadFailed }
        }
        #expect(sawPropertyRead, "the nil-converter signal was throttled away by a parse flood")
    }

    // MARK: - backlogOverflow uses exactly one channel

    /// `backlogOverflow` reports itself to `ErrorReporting.shared` on a geometric throttle
    /// of its own (#1030). Forwarding it here as well would report one occurrence through
    /// two channels and double-count the ones that pass that throttle.
    ///
    /// This test proves only the half it can see: that nothing reaches the analytics
    /// channel. The other half — that the `ErrorReporting` channel still fires, so the
    /// count is one rather than zero — is held by `MP3StreamDecoderBufferCapTests`, which
    /// drives a real overflow and asserts `reportedOverflowCount >= 1`. Neither test alone
    /// pins "exactly one"; they are complementary and must not be deleted independently.
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

        // The three AudioFileStream failures must be distinguishable from one another;
        // sharing a description would make them unattributable in Sentry.
        let open = MP3DecoderError.audioFileStreamOpenFailed(-39).localizedDescription
        let parse = MP3DecoderError.audioFileStreamParseFailed(-39).localizedDescription
        let property = MP3DecoderError.audioFileStreamPropertyReadFailed(-39).localizedDescription
        #expect(Set([open, parse, property]).count == 3)

        #expect(MP3DecoderError.bufferAllocationFailed.localizedDescription.contains("buffer"))

        // The Foundation fallback for a bare Swift error. Its presence would mean the
        // conformance is not being used and the events are ordinals again.
        #expect(!converter.contains("The operation couldn"))
    }

    /// This description reaches Sentry as part of the grouping key and PostHog as a
    /// property value, and `backlogOverflow` is the one case whose payload is unbounded.
    /// Interpolating the byte or packet counts would fragment one issue into one issue per
    /// drop and give the PostHog property unbounded cardinality — defeating the geometric
    /// throttle that exists to keep those reports groupable.
    @Test("backlogOverflow's description carries no unbounded values")
    func backlogOverflowDescriptionIsLowCardinality() throws {
        let first = MP3DecoderError
            .backlogOverflow(droppedBytes: 4_194_304, droppedPackets: 512)
            .localizedDescription
        let second = MP3DecoderError
            .backlogOverflow(droppedBytes: 8_388_608, droppedPackets: 1024)
            .localizedDescription

        #expect(first == second, "two different drops must produce one grouping key")
        #expect(!first.contains("4194304"))
        #expect(!first.contains("512"))
    }
}

/// The decoder paths that failed with no signal at all before #1036 — not even a yield
/// nothing was reading. Covered here at the decoder level: the forwarding from
/// `errorStream` to the analytics layer is proven by the suite above, so showing the site
/// yields completes the chain.
@Suite("MP3StreamDecoder Silent Failure Paths")
struct MP3StreamDecoderSilentPathTests {

    private actor Collector {
        var errors: [MP3DecoderError] = []
        func append(_ error: MP3DecoderError) { errors.append(error) }
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

    /// Awaits a decoder-queue seam's completion callback under a deadline, so a wedged
    /// queue fails the test rather than reading as success.
    private func awaitCompletion(
        timeout: Duration = .seconds(5),
        _ start: (@escaping @Sendable () -> Void) -> Void
    ) async -> Bool {
        let (signals, continuation) = AsyncStream<Void>.makeStream()
        start { continuation.finish() }
        return await withDeadline(timeout, fallback: false) {
            for await _ in signals {}
            return true
        }
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

        let returned = await awaitCompletion { done in
            decoder.deliverSyntheticPropertyChange(completion: done)
        }
        #expect(returned, "the property-change seam never returned")

        // Asserts the property-read kind specifically. A generic AudioFileStream kind here
        // could be satisfied by an incidental parse failure from the bytes above, which
        // would let this pass without ever exercising the path it names.
        #expect(
            await waitForKind(.audioFileStreamPropertyReadFailed, in: collector),
            "a failed data-format read produced no error — the path is silent again"
        )
    }

    /// The fatal-parse-status branch used to be an `if` body containing only a comment.
    /// Whether AudioToolbox returns a fatal status for any given payload is its business
    /// and not something a test can force, so the branch is tested directly instead.
    @Test(
        "Only a fatal parse status is reported",
        arguments: [
            (OSStatus(noErr), false),
            (kAudioFileStreamError_NotOptimized, false),
            (OSStatus(kAudioFileStreamError_InvalidFile), true)
        ]
    )
    func parseStatusReporting(status: OSStatus, expectsReport: Bool) async throws {
        let decoder = MP3StreamDecoder()
        let collector = Collector()
        let drainTask = drain(decoder, into: collector)
        defer { drainTask.cancel() }

        decoder.reportParseStatus(status)
        try await Task.sleep(for: .milliseconds(200))

        let reported = await collector.kinds.contains(.audioFileStreamParseFailed)
        #expect(
            reported == expectsReport,
            "status \(status): expected reported=\(expectsReport), got \(reported)"
        )
    }
}

#endif // !os(watchOS)
