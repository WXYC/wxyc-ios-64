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
/// On success, logs the duration and returns the result. On any error, returns
/// the fallback. What gets recorded depends on the kind of failure:
///
/// - **Cancellation** (``isCancellation(_:)`` — `CancellationError`, or
///   `URLError(.cancelled)` from `URLSession`) — logged at `.warning` with the
///   elapsed duration, and *not* sent to the error reporter. Cancellation is
///   usually routine teardown, but it is never nothing: it leaves the caller
///   holding `fallback`, which on a metadata read means a visibly degraded
///   card. The log line makes that visible and queryable (the app forwards
///   `.warning` and above to Sentry Logs) without minting an error event.
/// - **Anything else** — reported to the error reporter with the elapsed
///   duration.
///
/// - Parameters:
///   - context: A short label describing the operation (e.g., `"fetchPlaylist"`).
///     Used in log messages and error reports.
///   - category: The log category for filtering (e.g., `.network`, `.caching`).
///   - fallback: The value to return when the operation fails or is cancelled.
///   - errorReporter: Where to send non-cancellation errors. Defaults to the
///     global ``ErrorReporting/shared`` reporter.
///   - additionalData: Extra structured key-value pairs to attach to the error
///     report (in addition to the internally-measured `"duration"`). Lets callers
///     surface context — e.g. an API version — as a real, queryable property
///     rather than only inside the free-text `context` string. The measured
///     `"duration"` always wins on a key collision. Defaults to empty.
///   - operation: The async throwing closure to execute.
/// - Returns: The operation's result on success, or `fallback` on failure.
public func timedOperation<T: Sendable>(
    context: String,
    category: Category,
    fallback: T,
    errorReporter: any ErrorReporter = ErrorReporting.shared,
    additionalData: [String: String] = [:],
    operation: sending () async throws -> T
) async -> T {
    Log(.info, category: category, "\(context): starting")
    let timer = Timer.start()

    do {
        let result = try await operation()
        let duration = timer.duration()
        Log(.info, category: category, "\(context): succeeded in \(duration)s")
        return result
    } catch let error where isCancellation(error) {
        // Decision recorded for #812: make cancellation *visible* rather than
        // trying to classify who caused it.
        //
        // Cancellation used to return the fallback in complete silence, which
        // meant a `/proxy/metadata/album` request torn down mid-flight produced
        // a label-only detail card with no error event and no log line —
        // visually identical to the pre-enrichment race #812 is about, and
        // impossible to tell apart after the fact. The clients that hit it had
        // real network trouble (180-second QUIC read timeouts against the API),
        // so the silence was hiding a genuine failure mode.
        //
        // The obvious fix — report only when `!Task.isCancelled`, on the theory
        // that an uncancelled task means the network stack acted alone —
        // doesn't hold. ``isCancellation(_:)`` documents why: `URLError`
        // `.cancelled` can surface without the surrounding task's flag being
        // set, so a false reading proves nothing about origin. It would also
        // mint an error event every time iOS tears down in-flight requests on
        // app suspension, which is neither a failure nor rare.
        //
        // So: no origin classification, and no error report. A `.warning` log
        // carries the context and duration, which the app forwards to Sentry
        // Logs — queryable and correlatable, without the alerting weight and
        // issue-grouping of an event. If cancellations ever need to be actioned
        // rather than merely observed, that is a decision to make against this
        // data, not a guess to bake into the classifier.
        //
        // Worth being precise about what that buys, since the trigger rate is
        // identical to the error report's: this fires on routine teardown too —
        // a card dismissed mid-fetch, a `.task` cancelled by a scroll, iOS
        // tearing down in-flight requests on suspension. The distinction is the
        // instrument, not the volume. It also costs nothing incremental against
        // the Logs quota: the `.info` "starting" line above already emitted for
        // this same call, and `SentryLogsDestination` forwards `.info` and up,
        // so every operation that can reach this arm has already paid for a log
        // line. What would have been new is an *issue* per teardown.
        Log(.warning, category: category, "\(context): cancelled after \(timer.duration())s")
        return fallback
    } catch {
        let duration = timer.duration()
        var reportData = additionalData
        reportData["duration"] = "\(duration)"
        errorReporter.report(
            error,
            context: context,
            category: category,
            additionalData: reportData
        )
        return fallback
    }
}
