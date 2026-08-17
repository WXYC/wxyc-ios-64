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
