//
//  HTTPURLResponseValidationTests.swift
//  Core
//
//  Tests for HTTPURLResponse.validateSuccessStatus() extension.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Core

@Suite
struct HTTPURLResponseValidationTests {
    private static let testURL = URL(string: "https://api.wxyc.org/flowsheet")!

    @Test(arguments: [200, 201, 204, 299])
    func successStatusCodesDoNotThrow(statusCode: Int) throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        #expect(throws: Never.self) {
            try response.validateSuccessStatus()
        }
    }

    @Test(arguments: [100, 199, 300, 400, 404, 500, 503])
    func nonSuccessStatusCodesThrow(statusCode: Int) throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        #expect(throws: HTTPStatusError.self) {
            try response.validateSuccessStatus()
        }
    }

    @Test(arguments: [401, 500])
    func thrownErrorCarriesTheStatusCode(statusCode: Int) throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        #expect(throws: HTTPStatusError(statusCode: statusCode)) {
            try response.validateSuccessStatus()
        }
    }

    /// The whole point of `HTTPStatusError` is that a 401 and a 503 stay
    /// distinguishable in diagnostics. The NSError bridge is what PostHog's
    /// `ErrorEvent` (`nsError.code`/`nsError.domain`) and Sentry's event
    /// titles (`localizedDescription`) actually record — without explicit
    /// conformances every status collapses to code 1 with a generic message.
    @Test(arguments: [401, 429, 503])
    func nsErrorBridgeCarriesTheStatusCode(statusCode: Int) throws {
        let error = HTTPStatusError(statusCode: statusCode)
        let nsError = error as NSError

        #expect(nsError.code == statusCode)
        #expect(nsError.domain == "Core.HTTPStatusError")
        #expect(error.localizedDescription.contains("\(statusCode)"))
    }

    // MARK: - Retry-After (#957)

    /// A response advertising a delta-seconds `Retry-After` (RFC 9110
    /// §10.2.3) surfaces it on the thrown error, so a retrying consumer can
    /// prefer the server's own backoff over a hard-coded schedule.
    @Test
    func retryAfterHeaderPopulatesTheThrownError() throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "60"]
        )!
        #expect(throws: HTTPStatusError(statusCode: 429, retryAfter: 60)) {
            try response.validateSuccessStatus()
        }
    }

    /// A response with no `Retry-After` header leaves the field `nil` —
    /// today's behavior for every existing call site.
    @Test
    func missingRetryAfterHeaderLeavesTheFieldNil() throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: 503,
            httpVersion: nil,
            headerFields: nil
        )!
        do {
            try response.validateSuccessStatus()
            Issue.record("Expected validateSuccessStatus() to throw")
        } catch let error as HTTPStatusError {
            #expect(error.retryAfter == nil)
        }
    }

    /// RFC 9110 §10.2.3 also permits an HTTP-date `Retry-After`. Backend-Service's
    /// proxy limiter (`express-rate-limit` with `standardHeaders: true`) only ever
    /// emits delta-seconds, so an HTTP-date value is deliberately left unparsed —
    /// treated the same as a missing header — rather than carrying dead code for a
    /// format this app has never received on the wire.
    @Test
    func httpDateRetryAfterIsIgnored() throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"]
        )!
        do {
            try response.validateSuccessStatus()
            Issue.record("Expected validateSuccessStatus() to throw")
        } catch let error as HTTPStatusError {
            #expect(error.retryAfter == nil)
        }
    }

    /// `Double(String)` accepts more than RFC 9110's `delay-seconds` grammar:
    /// `"inf"`, `"infinity"`, and exponent forms like `"1e30"` all parse to
    /// finite-or-infinite values far outside anything `Duration.seconds(_:)`
    /// can represent, and building a `Duration` from one of those *traps* —
    /// so a header a hostile or broken intermediary controls could abort the
    /// process in a consumer that schedules a sleep from this value. Such
    /// values are unparseable as far as this app is concerned, and are
    /// reported the same way as every other malformed value: `nil`.
    @Test(arguments: ["inf", "infinity", "-inf", "nan", "1e30", "1e300", "99999999999999999999", "-1", "86401"])
    func unrepresentableRetryAfterValuesAreIgnored(headerValue: String) throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": headerValue]
        )!
        do {
            try response.validateSuccessStatus()
            Issue.record("Expected validateSuccessStatus() to throw")
        } catch let error as HTTPStatusError {
            #expect(error.retryAfter == nil, "\(headerValue) must not survive as a schedulable delay")
        }
    }

    /// The ceiling that rejects unrepresentable values must not clip any
    /// delay a real server would advertise — Backend-Service's proxy limiter
    /// sends `60`, and even a pathologically patient upstream stays well
    /// inside a day.
    @Test(arguments: [0.0, 1.0, 60.0, 3600.0, 86400.0])
    func plausibleRetryAfterValuesSurvive(seconds: TimeInterval) throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "\(Int(seconds))"]
        )!
        do {
            try response.validateSuccessStatus()
            Issue.record("Expected validateSuccessStatus() to throw")
        } catch let error as HTTPStatusError {
            #expect(error.retryAfter == seconds)
        }
    }

    /// The range check has to live at the *type* boundary, not only on the
    /// parse path. `init(statusCode:retryAfter:)` is public, so test doubles,
    /// stub fetchers, and any future non-`validateSuccessStatus()` producer can
    /// hand a consumer a value that traps `Duration.seconds(_:)` — which
    /// `PlaycutMetadataService` builds directly from this field. The invariant
    /// is only true if the initializer enforces it.
    @Test(arguments: [TimeInterval.infinity, -TimeInterval.infinity, TimeInterval.nan, 1e30, -1, 86_401])
    func publicInitializerRejectsUnrepresentableRetryAfter(retryAfter: TimeInterval) {
        let error = HTTPStatusError(statusCode: 429, retryAfter: retryAfter)
        #expect(error.retryAfter == nil, "\(retryAfter) must not survive construction as a schedulable delay")
    }

    /// The initializer must not clip a delay a real server would advertise.
    @Test(arguments: [0.0, 1.0, 60.0, 3600.0, 86_400.0])
    func publicInitializerKeepsPlausibleRetryAfter(retryAfter: TimeInterval) {
        #expect(HTTPStatusError(statusCode: 429, retryAfter: retryAfter).retryAfter == retryAfter)
    }

    /// `HTTPStatusError(statusCode:)` — the initializer used by
    /// `StubConcertsFetcher` and various test doubles — must keep compiling
    /// unchanged, defaulting the new field to `nil`.
    @Test
    func statusCodeOnlyInitializerDefaultsRetryAfterToNil() {
        let error = HTTPStatusError(statusCode: 404)
        #expect(error.retryAfter == nil)
    }

    /// Adding `retryAfter` must not perturb `errorCode`/`errorDomain`/
    /// `localizedDescription` — those feed PostHog's `ErrorEvent` and Sentry
    /// issue titles, and a change there would re-group existing issues.
    @Test
    func retryAfterDoesNotAffectNSErrorBridgeIdentity() throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "60"]
        )!
        do {
            try response.validateSuccessStatus()
            Issue.record("Expected validateSuccessStatus() to throw")
        } catch let error as HTTPStatusError {
            let nsError = error as NSError
            #expect(nsError.code == 429)
            #expect(nsError.domain == "Core.HTTPStatusError")
            #expect(error.localizedDescription.contains("429"))
        }
    }
}
