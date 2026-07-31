//
//  HTTPURLResponse+Validation.swift
//  Core
//
//  Extension on HTTPURLResponse providing HTTP status code validation for
//  success (2xx) responses, replacing duplicated inline checks across packages.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

extension HTTPURLResponse {
    /// Validates that the HTTP status code is in the 2xx success range.
    ///
    /// - Throws: ``HTTPStatusError`` carrying `statusCode` if the status code
    ///   is outside the 200...299 range.
    public func validateSuccessStatus() throws {
        guard (200...299).contains(statusCode) else {
            throw HTTPStatusError(statusCode: statusCode)
        }
    }
}

/// An HTTP response outside the 2xx success range.
///
/// Replaces the bare `URLError(.badServerResponse)` previously thrown by
/// ``HTTPURLResponse/validateSuccessStatus()`` for every non-2xx status —
/// that case carries no payload, so a 401 and a 503 were indistinguishable
/// in logs and Sentry breadcrumbs (both printed as `-1011 "(null)"`).
/// Carrying `statusCode` lets callers branch on the real status (e.g. a 401
/// triggering a reauthenticate-and-retry) and lets diagnostics show what
/// actually happened.
public struct HTTPStatusError: Error, Equatable {
    /// The non-2xx HTTP status code the server responded with.
    public let statusCode: Int

    public init(statusCode: Int) {
        self.statusCode = statusCode
    }
}

/// Diagnostics-sink bridging: without these conformances, the NSError bridge
/// collapses every status to `code 1` with a generic message — which is what
/// PostHog's `ErrorEvent` (`nsError.code`/`nsError.domain`) and Sentry event
/// titles record, re-creating the very 401-vs-503 blindness this type exists
/// to fix. `errorCode` carries the HTTP status so those sinks can group and
/// filter on it.
extension HTTPStatusError: CustomNSError, LocalizedError {
    /// Matches the default Swift-runtime bridge domain, so pre-conformance
    /// events keep grouping with post-conformance ones.
    public static let errorDomain = "Core.HTTPStatusError"

    public var errorCode: Int { statusCode }

    public var errorDescription: String? {
        "HTTP \(statusCode)"
    }
}
