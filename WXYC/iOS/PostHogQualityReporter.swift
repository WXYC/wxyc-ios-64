import Foundation
import PostHog
import Wallpaper

/// Reports thermal session summaries to PostHog.
final class PostHogQualityReporter: QualityMetricsReporter, @unchecked Sendable {

    init() {}

    func report(_ summary: QualitySessionSummary) {
        var properties: [String: Any] = [
            // Identity
            "shader_id": summary.shaderId,
            "flush_reason": summary.flushReason.rawValue,

            // Quality delivered
            "avg_wallpaper_fps": summary.avgWallpaperFPS,
            "avg_scale": summary.avgScale,
            "avg_lod": summary.avgLOD,
            "session_duration_seconds": summary.sessionDurationSeconds,

            // Thermal health
            "time_in_critical_seconds": summary.timeInCriticalSeconds,
            "throttle_event_count": summary.throttleEventCount,
            "oscillation_count": summary.oscillationCount,

            // Convergence
            "reached_stability": summary.reachedStability,
            "sessions_to_stability": summary.sessionsToStability as Any,
            "session_outcome": summary.sessionOutcome.rawValue
        ]

        // Add stable values only when stability was reached
        if let stableWallpaperFPS = summary.stableWallpaperFPS {
            properties["stable_wallpaper_fps"] = stableWallpaperFPS
        }
        if let stableScale = summary.stableScale {
            properties["stable_scale"] = stableScale
        }
        if let stableLOD = summary.stableLOD {
            properties["stable_lod"] = stableLOD
        }

        PostHogSDK.shared.capture("thermal_session_summary", properties: properties)
    }
}
