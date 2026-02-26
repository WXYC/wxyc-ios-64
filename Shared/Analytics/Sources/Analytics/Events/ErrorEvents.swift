//
//  ErrorEvents.swift
//  Analytics
//
//  Shared error event type for structured error capture across the app.
//  Replaces direct PostHogSDK.shared.capture(error:context:) calls.
//
//  Created by Jake Bromberg on 02/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A structured error event for analytics tracking.
///
/// Use this instead of calling `PostHogSDK.shared.capture(error:context:)` directly.
/// The event name is always `"error"` for consistency with the existing PostHog schema.
public struct ErrorEvent: AnalyticsEvent {
    public static let name = "error"

    public let error: String
    public let context: String
    public let code: Int?
    public let domain: String?

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "error": error,
            "context": context,
        ]
        if let code { props["code"] = code }
        if let domain { props["domain"] = domain }
        return props
    }

    public init(error: String, context: String, code: Int? = nil, domain: String? = nil) {
        self.error = error
        self.context = context
        self.code = code
        self.domain = domain
    }

    public init(error: Error, context: String) {
        let nsError = error as NSError
        self.error = error.localizedDescription
        self.context = context
        self.code = nsError.code
        self.domain = nsError.domain
    }
}
