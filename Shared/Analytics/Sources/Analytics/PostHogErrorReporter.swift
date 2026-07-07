//
//  PostHogErrorReporter.swift
//  Analytics
//
//  ErrorReporter implementation that logs locally and sends a structured
//  ErrorEvent to PostHog. Used by the watchOS app, which does not link
//  Sentry; the iOS app reports through CompositeErrorReporter instead. Both
//  paths emit the same ErrorEvent schema (the `error` property key) so a
//  single PostHog filter matches every build.
//
//  Created by Jake Bromberg on 03/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger
import struct Logger.Category

/// Reports errors to both the local log file and PostHog analytics.
///
/// Emits a structured ``ErrorEvent`` (event name `"error"`) through the
/// injected ``AnalyticsService``, matching `CompositeErrorReporter` so the
/// `error` property schema is identical across every reporter path. See the
/// package README for the canonical error-event schema.
///
/// Set as `ErrorReporting.shared` at app launch to unify all error
/// reporting behind a single call.
public struct PostHogErrorReporter: ErrorReporter {
    public static let shared = PostHogErrorReporter()

    private let analytics: any AnalyticsService

    /// - Parameter analytics: The sink the ``ErrorEvent`` is captured on.
    ///   Defaults to ``StructuredPostHogAnalytics/shared``.
    public init(analytics: any AnalyticsService = StructuredPostHogAnalytics.shared) {
        self.analytics = analytics
    }

    public func report(
        _ error: any Error,
        context: String,
        category: Category,
        additionalData: [String: String]
    ) {
        Log(.error, category: category, "\(context): \(error)")

        analytics.capture(ErrorEvent(
            error: error,
            context: context,
            category: category.rawValue,
            additionalData: additionalData
        ))
    }
}
