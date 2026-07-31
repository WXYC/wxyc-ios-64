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
}
