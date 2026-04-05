//
//  TimedOperation.swift
//  Core
//
//  Generic utility for wrapping async operations with timing, logging,
//  CancellationError handling, and error reporting. Reduces boilerplate
//  in network service layers that share this pattern.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger
import struct Logger.Category

/// Executes an async throwing operation with standardized timing, logging, and error handling.
///
/// On success, logs the duration and returns the result. On `CancellationError`, returns
/// the fallback silently (task cancellation is normal during cleanup). On any other error,
/// reports it via the error reporter with the elapsed duration and returns the fallback.
///
/// - Parameters:
///   - context: A short label describing the operation (e.g., `"fetchPlaylist"`).
///     Used in log messages and error reports.
///   - category: The log category for filtering (e.g., `.network`, `.caching`).
///   - fallback: The value to return when the operation fails or is cancelled.
///   - errorReporter: Where to send non-cancellation errors. Defaults to the
///     global ``ErrorReporting/shared`` reporter.
///   - operation: The async throwing closure to execute.
/// - Returns: The operation's result on success, or `fallback` on failure.
public func timedOperation<T: Sendable>(
    context: String,
    category: Category,
    fallback: T,
    errorReporter: any ErrorReporter = ErrorReporting.shared,
    operation: sending () async throws -> T
) async -> T {
    Log(.info, category: category, "\(context): starting")
    let timer = Timer.start()

    do {
        let result = try await operation()
        let duration = timer.duration()
        Log(.info, category: category, "\(context): succeeded in \(duration)s")
        return result
    } catch is CancellationError {
        return fallback
    } catch {
        let duration = timer.duration()
        errorReporter.report(
            error,
            context: context,
            category: category,
            additionalData: ["duration": "\(duration)"]
        )
        return fallback
    }
}
