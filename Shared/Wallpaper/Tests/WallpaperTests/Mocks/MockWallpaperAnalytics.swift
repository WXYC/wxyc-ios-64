//
//  MockWallpaperAnalytics.swift
//  WallpaperTests
//
//  Mock analytics for testing thermal quality control.
//  Captures recorded events and flush reasons for verification.
//
//  Created by Auto-Agent on 01/15/26.
//

@testable import Wallpaper
import Analytics
import Foundation

/// Mock analytics for testing that captures recorded events and flushes.
@MainActor
final class MockWallpaperAnalytics: AnalyticsService, @unchecked Sendable {

    var recordedEvents: [QualityAdjustmentEvent] = []
    var reportedSummaries: [QualitySessionSummary] = []
    var flushReasons: [QualityFlushReason] = []
    private var _events: [any AnalyticsEvent] = []

    nonisolated func capture<T: AnalyticsEvent>(_ event: T) {
        MainActor.assumeIsolated {
            _events.append(event)
            if let adjustmentEvent = event as? QualityAdjustmentEvent {
                recordedEvents.append(adjustmentEvent)
            }
            if let summary = event as? QualitySessionSummary {
                reportedSummaries.append(summary)
                // Extract flush reason from the summary
                flushReasons.append(summary.flushReason)
            }
        }
    }

    func reset() {
        recordedEvents.removeAll()
        reportedSummaries.removeAll()
        flushReasons.removeAll()
        _events.removeAll()
    }
}
