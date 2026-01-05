import Foundation
import PostHog
import Wallpaper

/// Reports thermal session summaries to PostHog.
final class PostHogThermalReporter: ThermalMetricsReporter, @unchecked Sendable {

    init() {}

    func report(_ summary: ThermalSessionSummary) {
        PostHogSDK.shared.capture("thermal_session_summary", properties: [
            // Identity
            "shader_id": summary.shaderId,
            "flush_reason": summary.flushReason.rawValue,

            // Quality delivered
            "avg_fps": summary.avgFPS,
            "avg_scale": summary.avgScale,
            "session_duration_seconds": summary.sessionDurationSeconds,

            // Thermal health
            "time_in_critical_seconds": summary.timeInCriticalSeconds,
            "throttle_event_count": summary.throttleEventCount,
            "oscillation_count": summary.oscillationCount,

            // Convergence
            "reached_stability": summary.reachedStability,
            "sessions_to_stability": summary.sessionsToStability as Any,
            "session_outcome": summary.sessionOutcome.rawValue
        ])
    }
}
