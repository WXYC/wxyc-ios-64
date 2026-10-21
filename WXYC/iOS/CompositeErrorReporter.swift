//
//  CompositeErrorReporter.swift
//  WXYC
//
//  ErrorReporter implementation that fans out error reports to local logging,
//  PostHog analytics, and Sentry crash reporting.
//
//  Created by Jake Bromberg on 03/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Foundation
import Logger
import Sentry

/// Reports errors to all three backends: local log, PostHog, and Sentry.
struct CompositeErrorReporter: ErrorReporter {
    private let analytics: any AnalyticsService

    /// - Parameter analytics: The sink PostHog reports go to. Defaults to
    ///   ``StructuredPostHogAnalytics/shared``.
    init(analytics: any AnalyticsService = StructuredPostHogAnalytics.shared) {
        self.analytics = analytics
    }

    func report(
        _ error: any Error,
        context: StaticString,
        category: LogCategory,
        additionalData: [String: String]
    ) {
        // 1. Local log
        Log(.error, category: category, "\(context): \(error)")

        // 2. PostHog. The static context is the call site's dedupe label.
        analytics.captureReportedError(
            error,
            context: String(describing: context),
            category: category.rawValue,
            additionalData: additionalData,
            dedupeLabel: context
        )

        // 3. Sentry
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: "\(context): \(error.localizedDescription)")
        event.extra = additionalData.merging(["category": category.rawValue]) { _, new in new }
        SentrySDK.capture(event: event)
    }
}
