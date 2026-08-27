//
//  RequestLineComposerTests.swift
//  MusicShareKit
//
//  Tests for the Request Line composer's send outcomes and inline failure state.
//
//  Created by Jake Bromberg on 08/04/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AnalyticsTesting
import Foundation
import Testing
@testable import MusicShareKit

@Suite("RequestLineComposer Tests")
@MainActor
struct RequestLineComposerTests {

    /// Composers here send through a `RequestSending` stub, so nothing touches
    /// `MusicShareKit.configuration` — that global is `nonisolated(unsafe)`,
    /// and suites that reconfigure it concurrently over-release its payload.
    private func makeComposer(
        result: Result<Void, RequestServiceError> = .success(()),
        analytics: MockStructuredAnalytics = MockStructuredAnalytics()
    ) -> (RequestLineComposer, StubSender, MockStructuredAnalytics) {
        let sender = StubSender(result: result)
        let composer = RequestLineComposer(
            source: "banner",
            requestSender: sender,
            analytics: analytics
        )
        return (composer, sender, analytics)
    }

    // MARK: - Nothing to send

    @Test("An empty composer has nothing to send")
    func emptyComposerCannotSend() async {
        let (composer, sender, analytics) = makeComposer()

        #expect(composer.canSend == false)
        #expect(await composer.send() == nil)
        #expect(await sender.invocationCount == 0)
        #expect(analytics.typedEvents(ofType: RequestLineSongRequested.self).isEmpty)
    }

    @Test("Whitespace alone has nothing to send", arguments: [" ", "\n", "   \n  "])
    func whitespaceOnlyCannotSend(text: String) async {
        let (composer, sender, _) = makeComposer()
        composer.text = text

        #expect(composer.canSend == false)
        #expect(await composer.send() == nil)
        #expect(await sender.invocationCount == 0)
    }

    // MARK: - Success

    @Test("A successful send reports sent and records the request")
    func successfulSendReportsSent() async {
        let (composer, sender, analytics) = makeComposer()
        composer.text = "  la paradoja by Juana Molina  "

        let outcome = await composer.send()

        #expect(outcome == .sent)
        #expect(composer.failure == nil)
        #expect(composer.isSending == false)
        #expect(await sender.sentMessages == ["la paradoja by Juana Molina"], "Sends the trimmed text")

        let events = analytics.typedEvents(ofType: RequestLineSongRequested.self)
        #expect(events.count == 1)
        #expect(events.first?.source == "banner")
    }

    // MARK: - Failure

    @Test("A failed send reports failed and says so inline")
    func failedSendReportsFailed() async {
        let (composer, _, analytics) = makeComposer(result: .failure(.serverError(statusCode: 500)))
        composer.text = "Back, Baby by Jessica Pratt"

        let outcome = await composer.send()

        #expect(outcome == .failed)
        #expect(composer.failure != nil)
        #expect(composer.isSending == false)
        #expect(analytics.typedEvents(ofType: RequestLineSongRequested.self).isEmpty)
    }

    // The sheet stays open on failure precisely so the listener doesn't have
    // to retype; losing the text would defeat the point.
    @Test("A failed send keeps what the listener typed")
    func failedSendPreservesText() async {
        let (composer, _, _) = makeComposer(result: .failure(.networkError(URLError(.notConnectedToInternet))))
        composer.text = "Back, Baby by Jessica Pratt"

        _ = await composer.send()

        #expect(composer.text == "Back, Baby by Jessica Pratt")
        #expect(composer.canSend, "A failed send must be retryable")
    }

    @Test("Editing after a failure clears the stale error")
    func editingClearsFailure() async {
        let (composer, _, _) = makeComposer(result: .failure(.serverError(statusCode: 500)))
        composer.text = "Back, Baby by Jessica Pratt"
        _ = await composer.send()
        #expect(composer.failure != nil)

        composer.text = "Back, Baby by Jessica Pratt!"

        #expect(composer.failure == nil)
    }

    // A shadow-banned listener (iOS#351 D2) gets a 403 that `RequestService`
    // swallows without throwing. The confirmation must be indistinguishable
    // from a real send — suppressing it here would be the tell.
    @Test("A swallowed shadow-ban is indistinguishable from a send")
    func shadowBanLooksLikeSuccess() async {
        let (composer, _, _) = makeComposer()
        composer.text = "Edits by Chuquimamani-Condori"

        #expect(await composer.send() == .sent)
        #expect(composer.failure == nil)
    }

    // MARK: - Failure classification

    // Pins the mapping in iOS#1011: the cause the listener sees must be
    // assertable as a case, not by matching the copy the view renders.
    @Test(
        "Each RequestServiceError classifies to the failure the listener should be told about",
        arguments: requestServiceErrorClassifications
    )
    func classifiesEachRequestServiceError(error: RequestServiceError, expected: RequestLineFailure) async {
        let (composer, _, _) = makeComposer(result: .failure(error))
        composer.text = "Back, Baby by Jessica Pratt"

        _ = await composer.send()

        #expect(composer.failure == expected)
    }

    // A shadow-banned listener is on the unauthenticated path (the whole
    // install base today), so ROM's ban response reaches this as a 403 with
    // no JWT — the same shape as a real outage. Rendering "the booth turned
    // that one down" for it would hand the ban away in the copy, which is
    // exactly the ban-probe-by-copy the 2026-08-27 correction to iOS#1011
    // rejected. This must classify indistinguishably from a transport
    // failure, not as a booth rejection.
    @Test("A 403 classifies as boothUnreachable, not boothRejected")
    func classifies403AsBoothUnreachable() async {
        let (composer, _, _) = makeComposer(result: .failure(.serverError(statusCode: 403)))
        composer.text = "Back, Baby by Jessica Pratt"

        _ = await composer.send()

        #expect(composer.failure == .boothUnreachable)
    }

    // Folding the `?? .boothUnreachable` fallback into `RequestLineFailure`
    // itself means an error that was never a `RequestServiceError` at all —
    // a raw `URLError`, say — takes the same defensive default a
    // `RequestServiceError` case it doesn't have a better story for takes.
    @Test("A non-RequestServiceError error defaults to boothUnreachable")
    func nonRequestServiceErrorDefaultsToBoothUnreachable() {
        let failure = RequestLineFailure(URLError(.notConnectedToInternet))

        #expect(failure == .boothUnreachable)
    }

    // MARK: - Failure telemetry

    // Pins the wire strings in iOS#1011: a fleet-wide rename flatlined a
    // PostHog series exactly this way in 3.2. The bare case name is the
    // value — not the interpolated `"boothRejected(500)"` the first attempt
    // shipped — so a `failure_cause` breakdown stays one series instead of
    // fragmenting per HTTP status.
    @Test(
        "A failed send reports failure_cause as the bare case name",
        arguments: [
            (RequestServiceError.authenticationFailed(URLError(.notConnectedToInternet)), "authUnavailable"),
            (RequestServiceError.invalidResponse, "boothUnreachable"),
            (RequestServiceError.serverError(statusCode: 403), "boothUnreachable"),
            (RequestServiceError.serverError(statusCode: 500), "boothRejected"),
        ]
    )
    func reportsFailureCauseAsBareCaseName(error: RequestServiceError, expectedCause: String) async throws {
        let (composer, _, analytics) = makeComposer(result: .failure(error))
        composer.text = "Back, Baby by Jessica Pratt"

        _ = await composer.send()

        let event = try #require(analytics.errorEvents.last)
        #expect(event.additionalData?["failure_cause"] == expectedCause)
    }

    // The status code is useful, but only under its own key — folding it
    // into `failure_cause` is exactly what fragments the breakdown.
    @Test("A boothRejected failure carries its status code under a separate key")
    func reportsStatusCodeUnderItsOwnKey() async throws {
        let (composer, _, analytics) = makeComposer(result: .failure(.serverError(statusCode: 502)))
        composer.text = "Back, Baby by Jessica Pratt"

        _ = await composer.send()

        let event = try #require(analytics.errorEvents.last)
        #expect(event.additionalData?["failure_cause"] == "boothRejected")
        #expect(event.additionalData?["status_code"] == "502")
    }

    // A cause that doesn't carry a status code must not grow one — a
    // stray `status_code` on an auth-unavailable drop would misattribute it.
    @Test("An authUnavailable failure carries no status_code key")
    func authUnavailableCarriesNoStatusCode() async throws {
        let (composer, _, analytics) = makeComposer(result: .failure(.authenticationFailed(URLError(.notConnectedToInternet))))
        composer.text = "Back, Baby by Jessica Pratt"

        _ = await composer.send()

        let event = try #require(analytics.errorEvents.last)
        #expect(event.additionalData?["status_code"] == nil)
    }

    // MARK: - Double-send guard

    @Test("A send already in flight blocks a second one")
    func inFlightSendBlocksAnother() async {
        let sender = GatedSender()
        let composer = RequestLineComposer(
            source: "station",
            requestSender: sender,
            analytics: MockStructuredAnalytics()
        )
        composer.text = "Call Your Name by Chuquimamani-Condori"

        async let first = composer.send()
        await sender.waitUntilInFlight()

        #expect(composer.isSending)
        #expect(composer.canSend == false)
        #expect(await composer.send() == nil, "The second tap must not reach the network")

        await sender.release()
        #expect(await first == .sent)
        #expect(await sender.invocationCount == 1)
    }
}

/// Extracted from the `@Test(arguments:)` call above — a large tuple array
/// inline blows the type-checker.
private nonisolated let requestServiceErrorClassifications: [(RequestServiceError, RequestLineFailure)] = [
    (.authenticationFailed(URLError(.notConnectedToInternet)), .authUnavailable),
    (.serverError(statusCode: 500), .boothRejected(statusCode: 500)),
    (.serverError(statusCode: 429), .boothRejected(statusCode: 429)),
    (.serverError(statusCode: 403), .boothUnreachable),
    (.invalidResponse, .boothUnreachable),
    (.encodingFailed, .boothUnreachable),
    (.networkError(URLError(.timedOut)), .boothUnreachable),
]

// MARK: - Test doubles

/// `RequestSending` that records what it was asked to send and returns a fixed result.
private actor StubSender: RequestSending {
    private let result: Result<Void, RequestServiceError>
    private(set) var sentMessages: [String] = []

    var invocationCount: Int { sentMessages.count }

    init(result: Result<Void, RequestServiceError>) {
        self.result = result
    }

    func sendRequest(message: String) async throws {
        sentMessages.append(message)
        try result.get()
    }
}

/// `RequestSending` that holds a send in flight until the test releases it, so
/// the double-send guard can be observed rather than raced.
private actor GatedSender: RequestSending {
    private var inFlight: CheckedContinuation<Void, Never>?
    private var announced: CheckedContinuation<Void, Never>?
    private var released = false
    private(set) var invocationCount = 0

    func sendRequest(message: String) async throws {
        invocationCount += 1
        announced?.resume()
        announced = nil
        guard !released else { return }
        await withCheckedContinuation { continuation in
            inFlight = continuation
        }
    }

    func waitUntilInFlight() async {
        guard invocationCount == 0 else { return }
        await withCheckedContinuation { continuation in
            announced = continuation
        }
    }

    func release() {
        released = true
        inFlight?.resume()
        inFlight = nil
    }
}
