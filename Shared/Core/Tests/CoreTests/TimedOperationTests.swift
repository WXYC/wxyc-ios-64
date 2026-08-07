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
        // `CancellationError` is structured concurrency's own signal — something in
        // the task tree asked to stop. Always silent, regardless of `Task.isCancelled`
        // (a cancelled child can raise it while this task is still alive). Only the
        // URLSession-originated `URLError(.cancelled)` gets the #812 treatment.
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

    @Test("forwards caller-supplied additionalData into the error report alongside duration")
    func forwardsCallerAdditionalDataOnError() async {
        let reporter = MockErrorReporter()

        let _ = await timedOperation(
            context: "fetchPlaylist(API v2)",
            category: .network,
            fallback: 0,
            errorReporter: reporter,
            additionalData: ["api_version": "v2"]
        ) {
            throw URLError(.badServerResponse)
        }

        let data = reporter.allReportedErrors.first?.additionalData
        #expect(data?["api_version"] == "v2")
        // The internally-measured duration is still present next to the extras.
        #expect(data?["duration"] != nil)
    }

    @Test("returns fallback on URLError(.cancelled) and reports it when the enclosing task is alive")
    func reportsNetworkOriginatedCancellation() async {
        // URLSession surfaces cancellation as URLError(.cancelled), which does not
        // bridge to CancellationError. When the enclosing Swift task has NOT been
        // cancelled, nobody asked for this — the network stack tore the request
        // down on its own — so it is a genuine failure and must reach the error
        // reporter, tagged so it can be told apart from an ordinary error (#812).
        let reporter = MockErrorReporter()

        let result = await timedOperation(
            context: "fetchPlaylist(API v2)",
            category: .network,
            fallback: 0,
            errorReporter: reporter
        ) {
            throw URLError(.cancelled)
        }

        #expect(result == 0, "The fallback is still returned — reporting must not change the value")
        #expect(reporter.allReportedErrors.count == 1)
        let reported = reporter.allReportedErrors.first
        #expect(reported?.context == "fetchPlaylist(API v2)")
        #expect(reported?.additionalData["cancellation"] == "network")
        #expect(reported?.additionalData["duration"] != nil)
    }

    @Test("stays silent on URLError(.cancelled) when the enclosing task was cancelled")
    func silentOnTaskOriginatedCancellation() async {
        // The user dismissed the view and SwiftUI cancelled the `.task`; URLSession
        // reports URLError(.cancelled) as a consequence. That is routine cleanup,
        // not a failure, and must stay out of Sentry (#812).
        let reporter = MockErrorReporter()

        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return await timedOperation(
                context: "fetchPlaylist(API v2)",
                category: .network,
                fallback: 0,
                errorReporter: reporter
            ) {
                throw URLError(.cancelled)
            }
        }
        task.cancel()
        let result = await task.value

        #expect(result == 0)
        #expect(reporter.allReportedErrors.isEmpty)
    }

    @Test("still reports a non-cancellation URLError raised inside a cancelled task")
    func cancelledTaskDoesNotSwallowRealErrors() async {
        // Guard against over-reading `Task.isCancelled`: a real failure must still
        // be reported even when the task happens to be cancelled, because the
        // silence is keyed on the error being a cancellation, not on the task state.
        let reporter = MockErrorReporter()

        let task = Task {
            while !Task.isCancelled {
                await Task.yield()
            }
            return await timedOperation(
                context: "fetchPlaylist(API v2)",
                category: .network,
                fallback: 0,
                errorReporter: reporter
            ) {
                throw URLError(.badServerResponse)
            }
        }
        task.cancel()
        _ = await task.value

        #expect(reporter.allReportedErrors.count == 1)
        #expect(reporter.allReportedErrors.first?.additionalData["cancellation"] == nil)
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
