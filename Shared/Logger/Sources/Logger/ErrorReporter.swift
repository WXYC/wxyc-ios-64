//
//  ErrorReporter.swift
//  Logger
//
//  Protocol for unified error reporting across logging, analytics, and crash
//  tracking backends. Concrete implementations live where their SDKs are
//  available (e.g., Analytics for PostHog, app level for Sentry).
//
//  Created by Jake Bromberg on 03/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A single entry point for reporting errors to all configured backends
/// (local logging, PostHog, Sentry, etc.).
///
/// Implementations must be thread-safe and ``Sendable``.
public protocol ErrorReporter: Sendable {
    /// Reports an error with contextual information.
    ///
    /// - Parameters:
    ///   - error: The error to report.
    ///   - context: A short description of where/why the error occurred
    ///     (e.g., `"DiskCache data(for:): failed to read file"`).
    ///   - category: The log category for filtering and organization.
    ///   - additionalData: Extra key-value pairs attached to the report.
    func report(
        _ error: any Error,
        context: String,
        category: Category,
        additionalData: [String: String]
    )
}

// MARK: - Convenience Defaults

public extension ErrorReporter {
    /// Reports an error with default category (`.general`) and no additional data.
    func report(
        _ error: any Error,
        context: String,
        category: Category = .general,
        additionalData: [String: String] = [:]
    ) {
        report(error, context: context, category: category, additionalData: additionalData)
    }
}
