import Foundation
@testable import Wallpaper

/// Mock reporter for testing that captures reported summaries.
@MainActor
final class MockThermalReporter: ThermalMetricsReporter {

    var reportedSummaries: [ThermalSessionSummary] = []

    func report(_ summary: ThermalSessionSummary) {
        reportedSummaries.append(summary)
    }

    func reset() {
        reportedSummaries.removeAll()
    }
}
