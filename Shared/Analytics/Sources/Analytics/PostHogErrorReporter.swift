//
//  PostHogErrorReporter.swift
//  Analytics
//
//  ErrorReporter implementation that logs locally and sends error events
//  to PostHog. This is the default reporter wired up at app launch before
//  Sentry is integrated.
//
//  Created by Jake Bromberg on 03/02/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger
import struct Logger.Category
import PostHog

/// Reports errors to both the local log file and PostHog analytics.
///
/// Set as `ErrorReporting.shared` at app launch to unify all error
/// reporting behind a single call.
public struct PostHogErrorReporter: ErrorReporter {
    public static let shared = PostHogErrorReporter()

    public init() {}

    public func report(
        _ error: any Error,
        context: String,
        category: Category,
        additionalData: [String: String]
    ) {
        Log(.error, category: category, "\(context): \(error)")

        var properties: [String: Any] = [
            "description": error.localizedDescription,
            "context": context,
        ]
        properties.merge(additionalData) { _, new in new }

        PostHogSDK.shared.capture("error", properties: properties)
    }
}
