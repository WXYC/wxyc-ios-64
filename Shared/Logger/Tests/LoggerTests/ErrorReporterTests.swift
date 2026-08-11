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

extension LoggerGlobalStateTests {

/// Serialized (both directly and via the `LoggerGlobalStateTests` parent,
/// which cascades `.serialized` to every nested suite) because
/// ErrorReporting.shared is process-global. A per-suite `.serialized` trait
/// alone only orders tests *within* this suite — it does not stop a sibling
/// suite from swapping `ErrorReporting.shared` out from under
/// `sharedCanBeSetAndRead` mid-test. Nesting under the shared parent closes
/// that gap without adding locking to `ErrorReporting` itself: a lock would
/// make each individual get and set atomic, but the race here spans a whole
/// test body — read the previous reporter, install a mock, report, restore —
/// and per-accessor atomicity does nothing for that sequence. Serializing the
/// suites is what makes it safe. The durable fix is injecting the reporter
/// rather than reaching for a mutable global at all, which is the same defect
/// family as issues #309 and #848 and is out of scope here.
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

}
