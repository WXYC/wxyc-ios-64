//
//  DecoderErrorClassificationTests.swift
//  Playback
//
//  Verifies that MP3 decoder failures reaching the controller are classified as
//  `.decodingError` rather than falling through to `.unknown`.
//
//  `classifyError` bridges with `error as NSError`, which always succeeds and hands
//  back a Swift-type domain matching none of the domain checks — so before issue
//  #1036 every decoder failure landed in `.unknown`, the same bucket #514 drained
//  for engine and session errors. Arrival at the analytics layer is not enough on
//  its own: an event nobody can group or filter is countable but not legible.
//
//  Created by Jake Bromberg on 08/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import PlaybackTestUtilities
import Core
@testable import Playback
@testable import PlaybackCore
#if !os(watchOS)
@testable import MP3StreamerModule
#endif

#if os(iOS) || os(tvOS)

@Suite("Decoder Error Classification")
@MainActor
struct DecoderErrorClassificationTests {

    private func waitForStreamError(
        _ harness: PlayerControllerTestHarness,
        timeout: Duration = .seconds(5)
    ) async -> StreamErrorEvent? {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let event = harness.streamErrorEvents.last { return event }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return harness.streamErrorEvents.last
    }

    /// Every decoder failure must classify as `.decodingError`. `.unknown` fails.
    @Test(
        "Decoder failures classify as decodingError",
        arguments: [
            MP3DecoderError.audioFileStreamOpenFailed(-50),
            MP3DecoderError.converterCreationFailed(-50),
            MP3DecoderError.bufferAllocationFailed
        ]
    )
    func decoderFailuresClassifyAsDecodingError(error: MP3DecoderError) async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.simulateError(error)

        let event = try #require(
            await waitForStreamError(harness),
            "no StreamErrorEvent captured for \(error.kind.rawValue)"
        )
        #expect(
            event.errorType == .decodingError,
            "\(error.kind.rawValue) classified as \(event.errorType.rawValue), expected decoding_error"
        )
        #expect(event.errorType != .unknown)
    }

    /// The classification is only half of legibility: `StreamErrorEvent` carries no
    /// free-form context, so `error_description` must name the failure and its
    /// `OSStatus` or the event cannot be acted on.
    @Test("The captured description names the failure and its status")
    func capturedDescriptionIsLegible() async throws {
        let harness = PlayerControllerTestHarness.make(for: .audioPlayerController)

        harness.simulateError(MP3DecoderError.converterCreationFailed(-50))

        let event = try #require(await waitForStreamError(harness))
        #expect(event.errorDescription.contains("converter"))
        #expect(event.errorDescription.contains("-50"))
        #expect(!event.errorDescription.contains("The operation couldn"))
    }
}

#endif // os(iOS) || os(tvOS)
