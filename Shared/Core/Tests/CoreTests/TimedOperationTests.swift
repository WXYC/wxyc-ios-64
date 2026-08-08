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
        // the task tree asked to stop. Never *reported*, regardless of
        // `Task.isCancelled` (a cancelled child can raise it while this task is
        // still alive). It takes the same `catch` arm as the URLSession-originated
        // `URLError(.cancelled)`, so it gets the #812 `.warning` log too — what
        // this test pins is the absence of an error event, not silence.
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

    @Test("returns fallback on URLError(.cancelled) without reporting")
    func noReportOnURLCancellation() async {
        // URLSession surfaces cancellation as URLError(.cancelled), which does not
        // bridge to CancellationError. It is classified from the error itself —
        // never from `Task.isCancelled`, which `isCancellation(_:)` documents as
        // unreliable in this direction — so it never mints an error event.
        //
        // The other half of the #812 decision, the `.warning` log that keeps a
        // degraded card from being invisible, is deliberately not asserted here:
        // `Logger` exposes only `addDestination`/`removeAllDestinations` over
        // shared mutable state, and that race is why `LoggerTests` is excluded
        // from every CI configuration (#800). Installing a recorder from this
        // suite would import the hazard into a suite that does run everywhere.
        let reporter = MockErrorReporter()

        let result = await timedOperation(
            context: "fetchPlaylist(API v2)",
            category: .network,
            fallback: 0,
            errorReporter: reporter
        ) {
            throw URLError(.cancelled)
        }

        #expect(result == 0)
        #expect(reporter.allReportedErrors.isEmpty, "Cancellation must not mint an error event")
    }

    @Test("stays silent in the reporter when the enclosing task was cancelled")
    func noReportOnTaskOriginatedCancellation() async {
        // The user dismissed the view and SwiftUI cancelled the `.task`; URLSession
        // reports URLError(.cancelled) as a consequence. Same treatment as any
        // other cancellation — the task's flag is not consulted.
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
        // The silence is keyed on the error being a cancellation, never on the
        // task's state — so a real failure is reported even when the surrounding
        // task happens to be cancelled.
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
