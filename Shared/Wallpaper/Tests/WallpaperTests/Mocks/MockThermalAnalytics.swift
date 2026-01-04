import Foundation
@testable import Wallpaper

/// Mock analytics for testing that captures recorded events and flushes.
@MainActor
final class MockThermalAnalytics: ThermalAnalytics {

    var recordedEvents: [ThermalAdjustmentEvent] = []
    var flushReasons: [ThermalFlushReason] = []

    func record(_ event: ThermalAdjustmentEvent) {
        recordedEvents.append(event)
    }

    func flush(reason: ThermalFlushReason) {
        flushReasons.append(reason)
    }

    func reset() {
        recordedEvents.removeAll()
        flushReasons.removeAll()
    }
}
