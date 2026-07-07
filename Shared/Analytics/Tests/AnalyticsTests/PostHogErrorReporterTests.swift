//
//  PostHogErrorReporterTests.swift
//  Analytics
//
//  Verifies PostHogErrorReporter emits the canonical ErrorEvent schema
//  (the `error` property key), matching CompositeErrorReporter, so the
//  error-event property keys don't drift between build generations.
//
//  Created by Jake Bromberg on 07/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Logger
@testable import Analytics
import AnalyticsTesting

@Suite("PostHogErrorReporter")
struct PostHogErrorReporterTests {

    @Test("Reports a structured ErrorEvent named `error` with unpacked NSError fields")
    func emitsCanonicalErrorEvent() throws {
        let mock = MockStructuredAnalytics()
        let reporter = PostHogErrorReporter(analytics: mock)
        let error = NSError(domain: "TestDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "boom",
        ])

        reporter.report(error, context: "WatchXYC", category: .network, additionalData: ["k": "v"])

        #expect(mock.capturedEventNames() == ["error"])
        #expect(mock.errorEvents.count == 1)

        let event = try #require(mock.errorEvents.first)
        #expect(event.error == "boom")
        #expect(event.context == "WatchXYC")
        #expect(event.code == 42)
        #expect(event.domain == "TestDomain")
        #expect(event.category == "Network")

        let props = try #require(event.properties)
        #expect(props["k"] as? String == "v")
    }

    @Test("Emitted properties use the canonical `error` key, not the legacy `description` key")
    func usesErrorKeyNotDescription() throws {
        let mock = MockStructuredAnalytics()
        let reporter = PostHogErrorReporter(analytics: mock)
        let error = NSError(domain: "TestDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "boom",
        ])

        reporter.report(error, context: "ctx", category: .general)

        let props = try #require(mock.errorEvents.first?.properties)
        #expect(props["error"] as? String == "boom")
        #expect(props["description"] == nil)
    }
}
