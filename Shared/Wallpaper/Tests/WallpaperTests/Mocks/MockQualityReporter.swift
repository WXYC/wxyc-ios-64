//
//  MockQualityReporter.swift
//  Wallpaper
//
//  Mock quality reporter for testing.
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

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
