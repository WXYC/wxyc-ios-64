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
    ///
    /// - Parameter dedupeLabel: Joins the error's type and message in the dedupe key. A
    ///   `StaticString` so only a compile-time constant can; runtime values go in `properties`.
    func captureException(_ error: any Error, properties: [String: Any]?, dedupeLabel: StaticString)
}

extension AnalyticsService {
    public func captureException(_ error: any Error, properties: [String: Any]?, dedupeLabel: StaticString) {}

    /// Sends an error object with no call-site label in its dedupe key.
    public func captureException(_ error: any Error, properties: [String: Any]?) {
        captureException(error, properties: properties, dedupeLabel: "")
    }
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
    ///
    /// - Parameter dedupeLabel: The call site's compile-time label for the exception's dedupe key.
    ///   `context` is a runtime string, so it is sent as a property and never enters the key.
    public func captureReportedError(
        _ error: any Error,
        context: String,
        category: String,
        additionalData: [String: String],
        dedupeLabel: StaticString = ""
    ) {
        captureError(error, context: context, category: category, additionalData: additionalData)
        captureException(
            error,
            properties: additionalData.merging(["context": context, "category": category]) { _, new in new },
            dedupeLabel: dedupeLabel
        )
    }
}
