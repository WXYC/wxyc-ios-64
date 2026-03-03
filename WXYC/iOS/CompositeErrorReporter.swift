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

import Foundation
import Logger
import PostHog
import Sentry

/// Reports errors to all three backends: local log, PostHog, and Sentry.
struct CompositeErrorReporter: ErrorReporter {
    func report(
        _ error: any Error,
        context: String,
        category: Category,
        additionalData: [String: String]
    ) {
        // 1. Local log
        Log(.error, category: category, "\(context): \(error)")

        // 2. PostHog
        var properties: [String: Any] = [
            "description": error.localizedDescription,
            "context": context,
        ]
        properties.merge(additionalData) { _, new in new }
        PostHogSDK.shared.capture("error", properties: properties)

        // 3. Sentry
        let event = Event(level: .error)
        event.message = SentryMessage(formatted: "\(context): \(error.localizedDescription)")
        event.extra = additionalData.merging(["category": category.rawValue]) { _, new in new }
        SentrySDK.capture(event: event)
    }
}
