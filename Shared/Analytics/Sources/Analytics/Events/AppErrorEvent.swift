//
//  AppErrorEvent.swift
//  Analytics
//
//  Structured analytics event used by CompositeErrorReporter to send errors to
//  PostHog. Carries a description, context, category, and an additional payload
//  merged on top of the base properties.
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Event fired by the app's error reporter when an error is reported.
///
/// Shares the `"error"` event name with `ErrorEvent` so PostHog aggregates both
/// shapes under the same row schema. Adds a `category` property closing the
/// PostHog/Sentry asymmetry — Sentry already carries `category.rawValue`.
public struct AppErrorEvent: AnalyticsEvent {
    public static let name = "error"   // preserves dashboard continuity
    public let description: String
    public let context: String
    public let category: String        // String at the boundary, matches the AppLaunch.buildType convention
    public let extra: [String: String]

    public init(description: String, context: String, category: String, extra: [String: String] = [:]) {
        self.description = description
        self.context = context
        self.category = category
        self.extra = extra
    }

    public var properties: [String: Any]? {
        var props: [String: Any] = [
            "description": description,
            "context": context,
            "category": category,
        ]
        props.merge(extra) { _, new in new }
        return props
    }
}
