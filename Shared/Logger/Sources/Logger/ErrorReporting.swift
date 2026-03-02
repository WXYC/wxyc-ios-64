//
//  ErrorReporting.swift
//  Logger
//
//  Global holder for the shared ErrorReporter instance. Set once at app
//  launch before any background work begins.
//
//  Created by Jake Bromberg on 03/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Global access point for the shared ``ErrorReporter``.
///
/// Set ``shared`` in your app's `init()` (before `body` is evaluated) to
/// wire up the concrete reporter. Tests should set a ``MockErrorReporter``
/// in `setUp` and restore ``NoOpErrorReporter()`` in `tearDown`.
///
/// ```swift
/// // In WXYCApp.init():
/// ErrorReporting.shared = PostHogErrorReporter.shared
/// ```
public enum ErrorReporting {
    /// The process-wide error reporter. Defaults to ``NoOpErrorReporter``.
    ///
    /// Set once at app launch on the main thread. The value is read from any
    /// thread, so callers must not mutate it after background work has started.
    public nonisolated(unsafe) static var shared: any ErrorReporter = NoOpErrorReporter()
}

/// A no-op error reporter that silently discards all errors.
/// Used as the default before a real reporter is configured.
public struct NoOpErrorReporter: ErrorReporter {
    public init() {}

    public func report(
        _ error: any Error,
        context: String,
        category: Category,
        additionalData: [String: String]
    ) {
        // Intentionally empty
    }
}
