//
//  MockErrorReporter.swift
//  LoggerTesting
//
//  Test double for ErrorReporter that records reported errors for
//  verification in unit tests.
//
//  Created by Jake Bromberg on 03/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
@_exported import struct Logger.Category
import Logger

/// A recorded error report for test assertions.
public struct ReportedError: Sendable {
    public let error: any Error
    public let context: String
    public let category: Category
    public let additionalData: [String: String]
}

/// Test double that records all calls to ``report(_:context:category:additionalData:)``.
///
/// Thread-safe via `NSLock` so it can be used from concurrent test contexts.
public final class MockErrorReporter: ErrorReporter, @unchecked Sendable {
    private let lock = NSLock()
    private var _errors: [ReportedError] = []

    public init() {}

    public func report(
        _ error: any Error,
        context: String,
        category: Category,
        additionalData: [String: String]
    ) {
        lock.withLock {
            _errors.append(ReportedError(
                error: error,
                context: context,
                category: category,
                additionalData: additionalData
            ))
        }
    }

    // MARK: - Query

    /// All errors reported so far.
    public var allReportedErrors: [ReportedError] {
        lock.withLock { _errors }
    }

    /// Errors reported with a specific context string.
    public func errors(in context: String) -> [ReportedError] {
        lock.withLock { _errors.filter { $0.context == context } }
    }

    /// Clears all recorded errors.
    public func reset() {
        lock.withLock { _errors.removeAll() }
    }
}
