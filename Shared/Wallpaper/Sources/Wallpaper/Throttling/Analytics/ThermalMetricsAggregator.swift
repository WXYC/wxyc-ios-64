import Foundation

/// Aggregates thermal adjustment events in memory and flushes summaries to a reporter.
///
/// This layer accumulates statistics from frequent optimization ticks (every 5s)
/// and only sends aggregated summaries to PostHog on session boundaries.
@MainActor
public final class ThermalMetricsAggregator: ThermalAnalytics {

    /// Threshold for considering optimization stable (no adjustments for this duration).
    public static let stabilityThreshold: TimeInterval = 30

    /// Optimization tick interval (for calculating time in critical).
    public static let tickInterval: TimeInterval = 5

    private let reporter: ThermalMetricsReporter

    // MARK: - Session State

    private var currentShaderId: String?
    private var sessionStart: Date?
    private var lastEventTime: Date?

    // MARK: - Running Aggregates

    private var fpsSum: Float = 0
    private var scaleSum: Float = 0
    private var sampleCount: Int = 0
    private var timeInCritical: TimeInterval = 0
    private var throttleEvents: Int = 0
    private var oscillations: Int = 0

    // MARK: - Tracking State

    private var lastFPS: Float?
    private var lastScale: Float?
    private var lastAdjustmentTime: Date?
    private var lastDirection: AdjustmentDirection?
    private var initialFPS: Float?
    private var initialScale: Float?

    private enum AdjustmentDirection {
        case down, up, none
    }

    /// Creates an aggregator with the specified reporter.
    ///
    /// - Parameter reporter: The reporter to send session summaries to.
    public init(reporter: ThermalMetricsReporter) {
        self.reporter = reporter
    }

    // MARK: - ThermalAnalytics

    public func record(_ event: ThermalAdjustmentEvent) {
        // Track shader changes
        if event.shaderId != currentShaderId {
            if currentShaderId != nil {
                flush(reason: .shaderChanged)
            }
            currentShaderId = event.shaderId
            sessionStart = event.timestamp
            initialFPS = event.fps
            initialScale = event.scale
        }

        // Accumulate stats
        fpsSum += event.fps
        scaleSum += event.scale
        sampleCount += 1

        // Track time in critical
        if event.thermalState == .critical {
            timeInCritical += Self.tickInterval
        }

        // Detect throttle events (quality reduced)
        if let lastFPS, let lastScale {
            if event.fps < lastFPS || event.scale < lastScale {
                throttleEvents += 1
            }
        }

        // Detect oscillations (direction changes)
        let currentDirection = determineDirection(
            currentFPS: event.fps,
            currentScale: event.scale,
            lastFPS: lastFPS,
            lastScale: lastScale
        )

        if currentDirection != .none, let last = lastDirection, last != .none, currentDirection != last {
            oscillations += 1
        }

        // Track last adjustment time
        let adjusted = (lastFPS != nil && event.fps != lastFPS) ||
                       (lastScale != nil && event.scale != lastScale)
        if adjusted {
            lastAdjustmentTime = event.timestamp
        }

        // Update tracking state
        lastFPS = event.fps
        lastScale = event.scale
        lastEventTime = event.timestamp
        if currentDirection != .none {
            lastDirection = currentDirection
        }
    }

    public func flush(reason: ThermalFlushReason) {
        guard sampleCount > 0,
              let shaderId = currentShaderId,
              let start = sessionStart else {
            return
        }

        // Use last event time if available, otherwise fall back to now
        let endTime = lastEventTime ?? Date()
        let sessionDuration = endTime.timeIntervalSince(start)
        let reachedStability = hasReachedStability
        let outcome = determineOutcome(sessionDuration: sessionDuration, reachedStability: reachedStability)

        let summary = ThermalSessionSummary(
            shaderId: shaderId,
            flushReason: reason,
            avgFPS: fpsSum / Float(sampleCount),
            avgScale: scaleSum / Float(sampleCount),
            sessionDurationSeconds: sessionDuration,
            timeInCriticalSeconds: timeInCritical,
            throttleEventCount: throttleEvents,
            oscillationCount: oscillations,
            reachedStability: reachedStability,
            sessionsToStability: nil, // Set by controller from profile
            sessionOutcome: outcome
        )

        reporter.report(summary)
        resetAggregates()
    }

    // MARK: - Private Helpers

    private var hasReachedStability: Bool {
        guard let lastAdj = lastAdjustmentTime else {
            // No adjustments ever made
            return true
        }
        // Use last event time to check stability, not wall clock
        let referenceTime = lastEventTime ?? Date()
        return referenceTime.timeIntervalSince(lastAdj) >= Self.stabilityThreshold
    }

    private func determineDirection(
        currentFPS: Float,
        currentScale: Float,
        lastFPS: Float?,
        lastScale: Float?
    ) -> AdjustmentDirection {
        guard let lastFPS, let lastScale else { return .none }

        let fpsChange = currentFPS - lastFPS
        let scaleChange = currentScale - lastScale

        // Use combined change to determine direction
        let netChange = fpsChange + scaleChange * 60 // Normalize scale to FPS-equivalent

        if abs(netChange) < 0.1 {
            return .none
        } else if netChange < 0 {
            return .down
        } else {
            return .up
        }
    }

    private func determineOutcome(
        sessionDuration: TimeInterval,
        reachedStability: Bool
    ) -> ThermalSessionOutcome {
        if sessionDuration < 30 {
            return .tooBrief
        }

        // Check if we never throttled
        if throttleEvents == 0 {
            if let initialFPS, let initialScale,
               initialFPS >= 59 && initialScale >= 0.99 {
                return .neverThrottled
            }
        }

        // Check if we started already throttled
        let startedThrottled: Bool
        if let initialFPS, let initialScale {
            startedThrottled = initialFPS < 60 || initialScale < 1.0
        } else {
            startedThrottled = false
        }

        if startedThrottled && throttleEvents == 0 && reachedStability {
            return .alreadyOptimized
        }

        if reachedStability {
            return .optimizedThisSession
        }

        return .stillOptimizing
    }

    private func resetAggregates() {
        fpsSum = 0
        scaleSum = 0
        sampleCount = 0
        timeInCritical = 0
        throttleEvents = 0
        oscillations = 0
        lastFPS = nil
        lastScale = nil
        lastEventTime = nil
        lastAdjustmentTime = nil
        lastDirection = nil
        initialFPS = nil
        initialScale = nil
        currentShaderId = nil
        sessionStart = nil
    }
}
