//
//  StructuredPostHogAnalytics.swift
//  Analytics
//
//  PostHog implementation of AnalyticsService using structured AnalyticsEvent types.
//
//  Created by Antigravity on 01/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PostHog

/// A concrete implementation of AnalyticsService that reports to PostHog.
public final class StructuredPostHogAnalytics: AnalyticsService, @unchecked Sendable {
    public static let shared = StructuredPostHogAnalytics()

    private init() {}

    public func capture<T: AnalyticsEvent>(_ event: T) {
        PostHogSDK.shared.capture(T.name, properties: event.properties)
    }
}
