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
    func capture(_ event: String, properties: [String: Any]?)
}

public extension AnalyticsService {
    func capture(_ event: String) {
        capture(event, properties: nil)
    }
}

// MARK: - PostHog Wrapper

public final class PostHogAnalytics: AnalyticsService, @unchecked Sendable {
    public static let shared = PostHogAnalytics()

    private init() {}

    public func capture(_ event: String, properties: [String: Any]?) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
