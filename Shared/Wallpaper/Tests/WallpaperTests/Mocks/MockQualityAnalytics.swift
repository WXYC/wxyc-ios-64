//
//  MockQualityAnalytics.swift
//  Wallpaper
//
//  Mock quality analytics for testing.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
@testable import Wallpaper

/// Mock analytics for testing that captures recorded events and flushes.
@MainActor
final class MockQualityAnalytics: QualityAnalytics {

    var recordedEvents: [QualityAdjustmentEvent] = []
    var flushReasons: [QualityFlushReason] = []

    func record(_ event: QualityAdjustmentEvent) {
        recordedEvents.append(event)
    }

    func flush(reason: QualityFlushReason) {
        flushReasons.append(reason)
    }

    func reset() {
        recordedEvents.removeAll()
        flushReasons.removeAll()
    }
}
