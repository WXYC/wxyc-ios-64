//
//  ErrorReporterTests.swift
//  Logger
//
//  Tests for the ErrorReporter protocol and ErrorReporting global holder.
//
//  Created by Jake Bromberg on 03/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Logger
import LoggerTesting

/// Serialized because ErrorReporting.shared is process-global.
@Suite("ErrorReporter", .serialized)
struct ErrorReporterTests {

    @Test("MockErrorReporter records reported errors")
    func mockRecordsErrors() {
        let mock = MockErrorReporter()
        let error = NSError(domain: "TestDomain", code: 42)

        mock.report(error, context: "test context", category: .general)

        let reported = mock.allReportedErrors
        #expect(reported.count == 1)
        #expect(reported.first?.context == "test context")
        #expect(reported.first?.category == .general)
        #expect((reported.first?.error as? NSError)?.code == 42)
    }

    @Test("ErrorReporting.shared can be set and read")
    func sharedCanBeSetAndRead() {
        let mock = MockErrorReporter()
        let previous = ErrorReporting.shared
        defer { ErrorReporting.shared = previous }

        ErrorReporting.shared = mock
        let error = NSError(domain: "Test", code: 1)
        ErrorReporting.shared.report(error, context: "shared test", category: .network)

        #expect(mock.allReportedErrors.count == 1)
    }

    @Test("Default NoOpErrorReporter discards silently")
    func defaultNoOpDiscardsSilently() {
        let noop = NoOpErrorReporter()
        let error = NSError(domain: "Test", code: 1)

        // Should not crash or store anything
        noop.report(error, context: "should discard", category: .general)
    }

    @Test("ErrorReporter default parameters work")
    func defaultParametersWork() {
        let mock = MockErrorReporter()

        let error = NSError(domain: "Test", code: 1)
        mock.report(error, context: "defaults test")

        let reported = mock.allReportedErrors
        #expect(reported.count == 1)
        #expect(reported.first?.category == .general)
        #expect(reported.first?.additionalData.isEmpty == true)
    }

    @Test("MockErrorReporter records additional data")
    func mockRecordsAdditionalData() {
        let mock = MockErrorReporter()
        let error = NSError(domain: "Test", code: 1)

        mock.report(error, context: "data test", category: .caching, additionalData: ["key": "value"])

        let reported = mock.allReportedErrors
        #expect(reported.first?.additionalData["key"] == "value")
    }

    @Test("MockErrorReporter reset clears all recorded errors")
    func resetClearsErrors() {
        let mock = MockErrorReporter()
        mock.report(NSError(domain: "T", code: 1), context: "a")
        mock.report(NSError(domain: "T", code: 2), context: "b")

        #expect(mock.allReportedErrors.count == 2)
        mock.reset()
        #expect(mock.allReportedErrors.isEmpty)
    }
}
