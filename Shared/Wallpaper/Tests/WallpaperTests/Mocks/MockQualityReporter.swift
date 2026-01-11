import Foundation
@testable import Wallpaper

/// Mock reporter for testing that captures reported summaries.
@MainActor
final class MockQualityReporter: QualityMetricsReporter {

    var reportedSummaries: [QualitySessionSummary] = []

    func report(_ summary: QualitySessionSummary) {
        reportedSummaries.append(summary)
    }

    func reset() {
        reportedSummaries.removeAll()
    }
}
