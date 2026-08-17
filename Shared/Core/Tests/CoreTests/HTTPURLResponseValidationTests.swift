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
    ///
    /// The error carries a non-nil `retryAfter` so this doubles as the guard
    /// that adding that field perturbs none of `errorCode`/`errorDomain`/
    /// `localizedDescription`: all three are computed from `statusCode` alone,
    /// and a change in any of them would re-group existing Sentry issues.
    @Test(arguments: [401, 429, 503])
    func nsErrorBridgeCarriesTheStatusCode(statusCode: Int) throws {
        let error = HTTPStatusError(statusCode: statusCode, retryAfter: .seconds(60))
        let nsError = error as NSError

        #expect(nsError.code == statusCode)
        #expect(nsError.domain == "Core.HTTPStatusError")
        #expect(error.localizedDescription.contains("\(statusCode)"))
    }

    // MARK: - Retry-After (#957)

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
        let error = try #require(throws: HTTPStatusError.self) {
            try response.validateSuccessStatus()
        }
        #expect(error.retryAfter == nil)
    }

    /// Everything outside RFC 9110's `delay-seconds` grammar (`1*DIGIT`) is
    /// rejected, and the ceiling and floor are pinned from just outside.
    ///
    /// The floating-point forms matter because a `Double`-based parser would
    /// accept every one of them: `"inf"`/`"nan"` directly, `"1e30"` as an
    /// exponent, and `"0x1p4"` as a hex float worth `16`. Several are values
    /// `Duration.seconds(_:)` traps on, which is why the parser is `Int(_:)`.
    /// `"-1"` is the realistic malformed case — a server computing
    /// `resetTime - now` and going negative — and `"86401"` pins the ceiling
    /// from above so a later `0...max` to `0..<max` slip is caught on both
    /// sides rather than only one.
    @Test(arguments: [
        "inf", "infinity", "-inf", "nan", "1e30", "1e300", "0x1p4", "60.5",
        "99999999999999999999", "-1", "86401",
        // RFC 9110 §10.2.3 also permits an HTTP-date `Retry-After`. Backend-Service's
        // proxy limiter (`express-rate-limit` with `standardHeaders: true`) only ever
        // emits delta-seconds, so an HTTP-date value is deliberately left unparsed —
        // treated the same as a missing header — rather than carrying dead code for a
        // format this app has never received on the wire.
        "Wed, 21 Oct 2026 07:28:00 GMT",
    ])
    func nonConformantRetryAfterValuesAreIgnored(headerValue: String) throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": headerValue]
        )!
        let error = try #require(throws: HTTPStatusError.self) {
            try response.validateSuccessStatus()
        }
        #expect(error.retryAfter == nil, "\(headerValue) must not survive as a schedulable delay")
    }

    /// A delta-seconds `Retry-After` (RFC 9110 §10.2.3) survives onto the
    /// thrown error alongside the status, so a retrying consumer can reason
    /// about the server's own backoff instead of only its hard-coded schedule.
    ///
    /// The rejection rules must not clip any delay a real server would
    /// advertise — Backend-Service's proxy limiter sends `60`, and even a
    /// pathologically patient upstream stays inside a day. `86400` is the
    /// ceiling from below, the other half of the boundary pin.
    @Test(arguments: [0, 1, 60, 3600, 86_400])
    func plausibleRetryAfterValuesSurvive(seconds: Int) throws {
        let response = HTTPURLResponse(
            url: HTTPURLResponseValidationTests.testURL,
            statusCode: 429,
            httpVersion: nil,
            headerFields: ["Retry-After": "\(seconds)"]
        )!
        let error = try #require(throws: HTTPStatusError.self) {
            try response.validateSuccessStatus()
        }
        #expect(error.statusCode == 429)
        #expect(error.retryAfter == .seconds(seconds))
    }

    /// `HTTPStatusError(statusCode:)` — the initializer used by
    /// `StubConcertsFetcher` and various test doubles — must keep compiling
    /// unchanged, defaulting the new field to `nil`.
    @Test
    func statusCodeOnlyInitializerDefaultsRetryAfterToNil() {
        let error = HTTPStatusError(statusCode: 404)
        #expect(error.retryAfter == nil)
    }
}
