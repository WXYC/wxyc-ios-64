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
}
