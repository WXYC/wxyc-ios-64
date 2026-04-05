//
//  JSONDecoderSharedTests.swift
//  Core
//
//  Tests for the JSONDecoder.shared static property.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Core

@Suite
struct JSONDecoderSharedTests {
    @Test
    func sharedReturnsAJSONDecoder() {
        let decoder = JSONDecoder.shared
        #expect(decoder is JSONDecoder)
    }

    @Test
    func sharedReturnsSameInstance() {
        let first = JSONDecoder.shared
        let second = JSONDecoder.shared
        #expect(first === second)
    }

    @Test
    func sharedDecodesJSON() throws {
        let json = #"{"name":"Autechre","album":"Confield"}"#.data(using: .utf8)!
        let result = try JSONDecoder.shared.decode(TestModel.self, from: json)
        #expect(result.name == "Autechre")
        #expect(result.album == "Confield")
    }
}

// MARK: - Test Helpers

private struct TestModel: Codable {
    let name: String
    let album: String
}
