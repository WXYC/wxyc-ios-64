import Foundation

/// Protocol for reporting thermal session summaries to analytics.
///
/// Only this layer sends data to the analytics backend.
/// Implementations should convert ThermalSessionSummary into the appropriate format.
@MainActor
public protocol ThermalMetricsReporter: Sendable {

    /// Reports a thermal session summary to analytics.
    ///
    /// - Parameter summary: The aggregated session metrics to report.
    func report(_ summary: ThermalSessionSummary)
}

/// A no-op reporter for testing or when analytics is disabled.
public final class NoOpThermalReporter: ThermalMetricsReporter, @unchecked Sendable {

    public init() {}

    public func report(_ summary: ThermalSessionSummary) {
        // No-op
    }
}
