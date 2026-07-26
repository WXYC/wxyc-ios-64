//
//  BackgroundRefreshControllerTests.swift
//  WXYC
//
//  Regression coverage for #676: BGTaskScheduler.Error(.unavailable) and
//  .notPermitted are expected, platform-driven no-ops (Simulator, macOS
//  "Designed for iPad") and must not reach Sentry, while genuine scheduling
//  failures still do.
//
//  Created by Jake Bromberg on 07/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import BackgroundTasks
import Foundation
import Logger
import struct Logger.Category
import Testing
@testable import WXYC

@Suite("BackgroundRefreshController")
struct BackgroundRefreshControllerTests {
    @Test("Does not report BGTaskScheduler.unavailable, the expected Simulator/macOS case")
    func doesNotReportUnavailable() {
        let scheduler = FakeBackgroundTaskScheduler(errorToThrow: BGTaskScheduler.Error(.unavailable))
        let reporter = FakeErrorReporter()

        BackgroundRefreshController.scheduleNext(scheduler: scheduler, errorReporter: reporter)

        #expect(reporter.reportedErrors.isEmpty)
    }

    @Test("Does not report BGTaskScheduler.notPermitted, the expected no-background-mode case")
    func doesNotReportNotPermitted() {
        let scheduler = FakeBackgroundTaskScheduler(errorToThrow: BGTaskScheduler.Error(.notPermitted))
        let reporter = FakeErrorReporter()

        BackgroundRefreshController.scheduleNext(scheduler: scheduler, errorReporter: reporter)

        #expect(reporter.reportedErrors.isEmpty)
    }

    @Test("Reports a genuine BGTaskScheduler failure")
    func reportsGenuineSchedulingFailure() {
        let scheduler = FakeBackgroundTaskScheduler(errorToThrow: BGTaskScheduler.Error(.tooManyPendingTaskRequests))
        let reporter = FakeErrorReporter()

        BackgroundRefreshController.scheduleNext(scheduler: scheduler, errorReporter: reporter)

        #expect(reporter.reportedErrors.count == 1)
        #expect(reporter.reportedErrors.first?.context == "BackgroundRefreshController.scheduleNext")
    }

    @Test("Reports a non-BGTaskScheduler error")
    func reportsGenericError() {
        let scheduler = FakeBackgroundTaskScheduler(errorToThrow: URLError(.notConnectedToInternet))
        let reporter = FakeErrorReporter()

        BackgroundRefreshController.scheduleNext(scheduler: scheduler, errorReporter: reporter)

        #expect(reporter.reportedErrors.count == 1)
    }

    @Test("Submits successfully without reporting anything")
    func submitsSuccessfully() {
        let scheduler = FakeBackgroundTaskScheduler(errorToThrow: nil)
        let reporter = FakeErrorReporter()

        BackgroundRefreshController.scheduleNext(scheduler: scheduler, errorReporter: reporter)

        #expect(scheduler.submittedRequests.count == 1)
        #expect(reporter.reportedErrors.isEmpty)
    }
}

// MARK: - Test Doubles

/// Fake `BackgroundTaskScheduling` that records submitted requests and can be
/// configured to throw, standing in for the real `BGTaskScheduler`, which
/// isn't functional in the test host process.
private final class FakeBackgroundTaskScheduler: BackgroundTaskScheduling {
    private(set) var submittedRequests: [BGTaskRequest] = []
    private let errorToThrow: (any Error)?

    init(errorToThrow: (any Error)?) {
        self.errorToThrow = errorToThrow
    }

    func submit(_ request: BGTaskRequest) throws {
        submittedRequests.append(request)
        if let errorToThrow {
            throw errorToThrow
        }
    }
}

/// Records reported errors for assertions, without depending on the
/// `LoggerTesting` package (not linked into this target).
private final class FakeErrorReporter: ErrorReporter, @unchecked Sendable {
    struct Report {
        let error: any Error
        let context: String
    }

    private let lock = NSLock()
    private var _reportedErrors: [Report] = []

    var reportedErrors: [Report] {
        lock.withLock { _reportedErrors }
    }

    func report(
        _ error: any Error,
        context: String,
        category: Category,
        additionalData: [String: String]
    ) {
        lock.withLock {
            _reportedErrors.append(Report(error: error, context: context))
        }
    }
}
