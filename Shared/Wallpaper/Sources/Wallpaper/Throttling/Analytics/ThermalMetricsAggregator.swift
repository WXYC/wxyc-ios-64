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

    private var wallpaperFPSSum: Float = 0
    private var scaleSum: Float = 0
    private var lodSum: Float = 0
    private var sampleCount: Int = 0
    private var timeInCritical: TimeInterval = 0
    private var throttleEvents: Int = 0
    private var oscillations: Int = 0

    // MARK: - Tracking State

    private var lastWallpaperFPS: Float?
    private var lastScale: Float?
    private var lastLOD: Float?
    private var lastAdjustmentTime: Date?
    private var lastDirection: AdjustmentDirection?
    private var initialWallpaperFPS: Float?
    private var initialScale: Float?
    private var initialLOD: Float?

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
            initialWallpaperFPS = event.wallpaperFPS
            initialScale = event.scale
            initialLOD = event.lod
        }

        // Accumulate stats
        wallpaperFPSSum += event.wallpaperFPS
        scaleSum += event.scale
        lodSum += event.lod
        sampleCount += 1

        // Track time in critical
        if event.thermalState == .critical {
            timeInCritical += Self.tickInterval
        }

        // Detect throttle events (quality reduced)
        if let lastWallpaperFPS, let lastScale, let lastLOD {
            if event.wallpaperFPS < lastWallpaperFPS || event.scale < lastScale || event.lod < lastLOD {
                throttleEvents += 1
            }
        }

        // Detect oscillations (direction changes)
        let currentDirection = determineDirection(
            currentWallpaperFPS: event.wallpaperFPS,
            currentScale: event.scale,
            currentLOD: event.lod,
            lastWallpaperFPS: lastWallpaperFPS,
            lastScale: lastScale,
            lastLOD: lastLOD
        )

        if currentDirection != .none, let last = lastDirection, last != .none, currentDirection != last {
            oscillations += 1
        }

        // Track last adjustment time
        let adjusted = (lastWallpaperFPS != nil && event.wallpaperFPS != lastWallpaperFPS) ||
                       (lastScale != nil && event.scale != lastScale) ||
                       (lastLOD != nil && event.lod != lastLOD)
        if adjusted {
            lastAdjustmentTime = event.timestamp
        }

        // Update tracking state
        lastWallpaperFPS = event.wallpaperFPS
        lastScale = event.scale
        lastLOD = event.lod
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
            avgWallpaperFPS: wallpaperFPSSum / Float(sampleCount),
            avgScale: scaleSum / Float(sampleCount),
            avgLOD: lodSum / Float(sampleCount),
            sessionDurationSeconds: sessionDuration,
            timeInCriticalSeconds: timeInCritical,
            throttleEventCount: throttleEvents,
            oscillationCount: oscillations,
            reachedStability: reachedStability,
            sessionsToStability: nil, // Set by controller from profile
            sessionOutcome: outcome,
            stableWallpaperFPS: reachedStability ? lastWallpaperFPS : nil,
            stableScale: reachedStability ? lastScale : nil,
            stableLOD: reachedStability ? lastLOD : nil
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
        currentWallpaperFPS: Float,
        currentScale: Float,
        currentLOD: Float,
        lastWallpaperFPS: Float?,
        lastScale: Float?,
        lastLOD: Float?
    ) -> AdjustmentDirection {
        guard let lastWallpaperFPS, let lastScale, let lastLOD else { return .none }

        let fpsChange = currentWallpaperFPS - lastWallpaperFPS
        let scaleChange = currentScale - lastScale
        let lodChange = currentLOD - lastLOD

        // Use combined change to determine direction
        // Normalize scale and LOD to wallpaperFPS-equivalent
        let netChange = fpsChange + scaleChange * 60 + lodChange * 60

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
            if let initialWallpaperFPS, let initialScale, let initialLOD,
               initialWallpaperFPS >= 59 && initialScale >= 0.99 && initialLOD >= 0.99 {
                return .neverThrottled
            }
        }

        // Check if we started already throttled
        let startedThrottled: Bool
        if let initialWallpaperFPS, let initialScale, let initialLOD {
            startedThrottled = initialWallpaperFPS < 60 || initialScale < 1.0 || initialLOD < 1.0
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
        wallpaperFPSSum = 0
        scaleSum = 0
        lodSum = 0
        sampleCount = 0
        timeInCritical = 0
        throttleEvents = 0
        oscillations = 0
        lastWallpaperFPS = nil
        lastScale = nil
        lastLOD = nil
        lastEventTime = nil
        lastAdjustmentTime = nil
        lastDirection = nil
        initialWallpaperFPS = nil
        initialScale = nil
        initialLOD = nil
        currentShaderId = nil
        sessionStart = nil
    }
}
