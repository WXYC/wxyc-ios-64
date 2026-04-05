//
//  TimedOperationTests.swift
//  Core
//
//  Tests for the timedOperation utility function that wraps async operations
//  with timing, logging, error handling, and fallback behavior.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Logger
import LoggerTesting
@testable import Core

// MARK: - TimedOperation Tests

@Suite("TimedOperation Tests")
struct TimedOperationTests {
    @Test("returns the result of a successful operation")
    func returnsResultOnSuccess() async {
        let result = await timedOperation(
            context: "test",
            category: .network,
            fallback: "fallback"
        ) {
            "success"
        }

        #expect(result == "success")
    }

    @Test("returns fallback when the operation throws")
    func returnsFallbackOnError() async {
        let result = await timedOperation(
            context: "test",
            category: .network,
            fallback: "fallback"
        ) {
            throw URLError(.notConnectedToInternet)
            return "unreachable"
        }

        #expect(result == "fallback")
    }

    @Test("returns fallback on CancellationError without reporting")
    func returnsFallbackOnCancellationError() async {
        let reporter = MockErrorReporter()

        let result = await timedOperation(
            context: "test",
            category: .network,
            fallback: 0,
            errorReporter: reporter
        ) {
            throw CancellationError()
            return 42
        }

        #expect(result == 0)
        #expect(reporter.allReportedErrors.isEmpty)
    }

    @Test("reports non-cancellation errors to the error reporter")
    func reportsErrorsToReporter() async {
        let reporter = MockErrorReporter()

        let _ = await timedOperation(
            context: "fetchWidgets",
            category: .network,
            fallback: [String](),
            errorReporter: reporter
        ) {
            throw URLError(.badServerResponse)
            return ["widget"]
        }

        #expect(reporter.allReportedErrors.count == 1)
        let reported = reporter.allReportedErrors.first
        #expect(reported?.context == "fetchWidgets")
        #expect(reported?.category == .network)
        #expect(reported?.additionalData["duration"] != nil)
    }

    @Test("includes duration in additional data for reported errors")
    func includesDurationInErrorReport() async {
        let reporter = MockErrorReporter()

        let _ = await timedOperation(
            context: "slowFetch",
            category: .caching,
            fallback: "",
            errorReporter: reporter
        ) {
            throw NSError(domain: "test", code: 1)
            return "never"
        }

        let duration = reporter.allReportedErrors.first?.additionalData["duration"]
        #expect(duration != nil)
    }

    @Test("passes through the return type correctly for non-optional types")
    func worksWithNonOptionalTypes() async {
        let result: Int = await timedOperation(
            context: "intOp",
            category: .general,
            fallback: -1
        ) {
            42
        }

        #expect(result == 42)
    }

    @Test("passes through the return type correctly for optional types")
    func worksWithOptionalTypes() async {
        let result: String? = await timedOperation(
            context: "optOp",
            category: .general,
            fallback: nil
        ) {
            "hello"
        }

        #expect(result == "hello")
    }

    @Test("returns nil fallback for optional types on error")
    func returnsNilFallbackOnError() async {
        let result: String? = await timedOperation(
            context: "optOp",
            category: .general,
            fallback: nil
        ) {
            throw URLError(.timedOut)
            return "unreachable"
        }

        #expect(result == nil)
    }
}
