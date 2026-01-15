//
//  MockStructuredAnalytics.swift
//  AnalyticsTesting
//
//  Test double for AnalyticsService that records captured events for verification
//  in unit tests without sending data to a real analytics backend.
//
//  Created by Auto-Agent on 01/24/25.
//

import Analytics
import Foundation

public final class MockStructuredAnalytics: AnalyticsService, @unchecked Sendable {
    public private(set) var events: [AnalyticsEvent] = []
    
    public init() {}
    
    public func capture(_ event: AnalyticsEvent) {
        events.append(event)
    }
    
    public func reset() {
        events.removeAll()
    }
}
