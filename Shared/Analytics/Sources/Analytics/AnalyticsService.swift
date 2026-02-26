//
//  AnalyticsService.swift
//  Analytics
//
//  Protocol for analytics tracking
//
//  Created by Jake Bromberg on 11/11/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import PostHog

// MARK: - Analytics Protocol

public protocol AnalyticsService: Sendable {
    /// Captures a structured analytics event.
    func capture<T: AnalyticsEvent>(_ event: T)
}

// MARK: - Error Capture Convenience

extension AnalyticsService {
    /// Captures a structured error event with a string description.
    public func captureError(
        _ error: String,
        context: String,
        code: Int? = nil,
        domain: String? = nil
    ) {
        capture(ErrorEvent(error: error, context: context, code: code, domain: domain))
    }

    /// Captures a structured error event from an `Error` value.
    public func captureError(_ error: Error, context: String) {
        capture(ErrorEvent(error: error, context: context))
    }
}
