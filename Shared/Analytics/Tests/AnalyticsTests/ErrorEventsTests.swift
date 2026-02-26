//
//  ErrorEventsTests.swift
//  Analytics
//
//  Tests for the shared ErrorEvent type and captureError convenience methods.
//
//  Created by Jake Bromberg on 02/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics
import AnalyticsTesting

@Suite("ErrorEvent")
struct ErrorEventsTests {

    // MARK: - Event Name

    @Test("Event name is 'error'")
    func eventName() {
        #expect(ErrorEvent.name == "error")
    }

    // MARK: - Property Serialization

    @Test("Properties include error and context")
    func basicProperties() {
        let event = ErrorEvent(error: "Something went wrong", context: "DiskCache")
        let props = try! #require(event.properties)

        #expect(props["error"] as? String == "Something went wrong")
        #expect(props["context"] as? String == "DiskCache")
    }

    @Test("Optional code and domain are included when provided")
    func optionalProperties() throws {
        let event = ErrorEvent(
            error: "File not found",
            context: "DiskCache",
            code: -1,
            domain: "NSCocoaErrorDomain"
        )
        let props = try #require(event.properties)

        #expect(props["error"] as? String == "File not found")
        #expect(props["context"] as? String == "DiskCache")
        #expect(props["code"] as? Int == -1)
        #expect(props["domain"] as? String == "NSCocoaErrorDomain")
    }

    @Test("Optional code and domain are omitted when nil")
    func nilOptionalProperties() throws {
        let event = ErrorEvent(error: "Timeout", context: "Network")
        let props = try #require(event.properties)

        #expect(props["code"] == nil)
        #expect(props["domain"] == nil)
    }

    @Test("Error initializer extracts localizedDescription, code, and domain")
    func errorInitializer() throws {
        let nsError = NSError(domain: "TestDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Test error description"
        ])
        let event = ErrorEvent(error: nsError, context: "UnitTest")

        #expect(event.error == "Test error description")
        #expect(event.context == "UnitTest")
        #expect(event.code == 42)
        #expect(event.domain == "TestDomain")
    }
}

@Suite("AnalyticsService.captureError")
struct CaptureErrorConvenienceTests {

    @Test("captureError with string captures an ErrorEvent")
    func captureErrorString() {
        let mock = MockStructuredAnalytics()
        mock.captureError("Decode failed", context: "PlaylistFetcher")

        #expect(mock.errorEvents.count == 1)
        #expect(mock.errorEvents.first?.error == "Decode failed")
        #expect(mock.errorEvents.first?.context == "PlaylistFetcher")
    }

    @Test("captureError with Error captures an ErrorEvent")
    func captureErrorError() {
        let nsError = NSError(domain: "TestDomain", code: 99, userInfo: [
            NSLocalizedDescriptionKey: "OS error"
        ])
        let mock = MockStructuredAnalytics()
        mock.captureError(nsError, context: "CacheCoordinator")

        #expect(mock.errorEvents.count == 1)
        #expect(mock.errorEvents.first?.error == "OS error")
        #expect(mock.errorEvents.first?.context == "CacheCoordinator")
        #expect(mock.errorEvents.first?.code == 99)
        #expect(mock.errorEvents.first?.domain == "TestDomain")
    }

    @Test("captureError with string and code captures an ErrorEvent")
    func captureErrorStringWithCode() {
        let mock = MockStructuredAnalytics()
        mock.captureError("HTTP error", context: "API", code: 500, domain: "HTTPDomain")

        #expect(mock.errorEvents.count == 1)
        #expect(mock.errorEvents.first?.error == "HTTP error")
        #expect(mock.errorEvents.first?.code == 500)
        #expect(mock.errorEvents.first?.domain == "HTTPDomain")
    }
}
