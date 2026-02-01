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
