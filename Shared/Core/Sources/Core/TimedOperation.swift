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
/// the fallback. Whether the error is reported depends on what kind of failure
/// it was:
///
/// - **`CancellationError`** — structured concurrency's own signal. Always
///   silent: something in the task tree asked to stop.
/// - **`URLError(.cancelled)` while the enclosing task is cancelled** — the
///   caller went away (a SwiftUI `.task` torn down on dismissal, say) and
///   `URLSession` reported the consequence. Silent; routine cleanup.
/// - **`URLError(.cancelled)` while the enclosing task is alive** — nobody
///   asked for this; the network stack tore the request down on its own.
///   Reported, tagged `cancellation: network` so it stays separable from an
///   ordinary failure.
/// - **Anything else** — reported with the elapsed duration.
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
        // Decision recorded for #812: report network-originated cancellation,
        // stay silent on task-originated cancellation.
        //
        // Returning the fallback for every cancellation used to be silent
        // across the board, which meant a `/proxy/metadata/album` request the
        // network stack killed on its own produced a label-only detail card
        // with no Sentry event and no log line — visually identical to the
        // pre-enrichment race this ticket is about, and impossible to tell
        // apart after the fact. The clients that hit it had real trouble
        // (180-second QUIC read timeouts against the API), so the silence was
        // hiding a genuine failure mode behind what looks like user-initiated
        // dismissal.
        //
        // `Task.isCancelled` is the discriminator: when the enclosing task is
        // cancelled, someone asked to stop and `URLError(.cancelled)` is just
        // the consequence. When it isn't, nobody asked. `CancellationError` is
        // never reported either way — it's structured concurrency's own
        // signal, and a cancelled child can raise it while this task is very
        // much alive.
        guard error is URLError, !Task.isCancelled else {
            return fallback
        }
        let duration = timer.duration()
        var reportData = additionalData
        reportData["duration"] = "\(duration)"
        // Tagged so these stay separable from ordinary failures in Sentry —
        // filterable, and mutable on their own if they ever get noisy.
        reportData["cancellation"] = "network"
        errorReporter.report(
            error,
            context: context,
            category: category,
            additionalData: reportData
        )
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
