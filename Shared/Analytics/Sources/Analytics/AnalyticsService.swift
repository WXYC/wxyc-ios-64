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

// MARK: - Analytics Protocol

public protocol AnalyticsService: Sendable {
    /// Captures a structured analytics event.
    func capture<T: AnalyticsEvent>(_ event: T)

    /// Sends an error object to PostHog error tracking. Defaults to a no-op so
    /// conformers that only record events need not implement it.
    func captureException(_ error: any Error, properties: [String: Any]?)
}

extension AnalyticsService {
    public func captureException(_ error: any Error, properties: [String: Any]?) {}
}

// MARK: - Error Capture Convenience

extension AnalyticsService {
    /// Captures a structured error event with a string description.
    public func captureError(
        _ error: String,
        context: String,
        code: Int? = nil,
        domain: String? = nil,
        category: String? = nil,
        additionalData: [String: String]? = nil
    ) {
        capture(ErrorEvent(error: error, context: context, code: code, domain: domain, category: category, additionalData: additionalData))
    }

    /// Captures a structured error event from an `Error` value.
    public func captureError(_ error: Error, context: String, category: String? = nil, additionalData: [String: String]? = nil) {
        capture(ErrorEvent(error: error, context: context, category: category, additionalData: additionalData))
    }

    /// Captures the custom `error` event and a PostHog exception for the same error. The event keeps
    /// existing insights (shared with Android) working; the exception feeds error tracking.
    public func captureReportedError(
        _ error: any Error,
        context: String,
        category: String,
        additionalData: [String: String]
    ) {
        captureError(error, context: context, category: category, additionalData: additionalData)
        captureException(error, properties: additionalData.merging(["context": context, "category": category]) { _, new in new })
    }
}
