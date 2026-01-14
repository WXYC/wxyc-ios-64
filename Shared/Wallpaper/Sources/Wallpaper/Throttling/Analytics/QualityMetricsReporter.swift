//
//  QualityMetricsReporter.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 01/03/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Protocol for reporting thermal session summaries to analytics.
///
/// Only this layer sends data to the analytics backend.
/// Implementations should convert QualitySessionSummary into the appropriate format.
@MainActor
public protocol QualityMetricsReporter: Sendable {

    /// Reports a thermal session summary to analytics.
    ///
    /// - Parameter summary: The aggregated session metrics to report.
    func report(_ summary: QualitySessionSummary)
}

/// A no-op reporter for testing or when analytics is disabled.
public final class NoOpQualityReporter: QualityMetricsReporter, @unchecked Sendable {

    public init() {}

    public func report(_ summary: QualitySessionSummary) {
        // No-op
    }
}
