//
//  PostHogPlaybackAnalytics.swift
//  PlaybackCore
//
//  PostHog implementation of PlaybackAnalytics.
//

import Foundation
import PostHog

/// PostHog implementation of PlaybackAnalytics.
///
/// Captures playback events to PostHog for analytics.
@MainActor
public final class PostHogPlaybackAnalytics: PlaybackAnalytics {

    // MARK: - Singleton

    public static let shared = PostHogPlaybackAnalytics()

    // MARK: - Initialization

    public init() {}

    // MARK: - PlaybackAnalytics

    public func capture(_ event: PlaybackStartedEvent) {
        var properties: [String: Any] = ["source": "RadioPlayerController"]
        properties["reason"] = event.reason
        PostHogSDK.shared.capture("play", properties: properties)
    }

    public func capture(_ event: PlaybackStoppedEvent) {
        var properties: [String: Any] = [
            "source": "RadioPlayerController",
            "duration": event.duration
        ]
        if let reason = event.reason {
            properties["reason"] = reason
        }
        PostHogSDK.shared.capture("pause", properties: properties)
    }

    public func capture(_ event: StallRecoveryEvent) {
        PostHogSDK.shared.capture(
            "stall_recovery",
            properties: [
                "player_type": event.playerType.rawValue,
                "successful": event.successful,
                "attempts": event.attempts,
                "stall_duration": event.stallDuration,
                "reason": event.reason.rawValue,
                "recovery_method": event.recoveryMethod.rawValue
            ]
        )
    }

    public func capture(_ event: InterruptionEvent) {
        PostHogSDK.shared.capture(
            "interruption",
            properties: [
                "type": String(describing: event.type)
            ]
        )
    }

    public func capture(_ event: ErrorEvent) {
        PostHogSDK.shared.capture(
            "error",
            properties: [
                "error": event.error,
                "context": event.context
            ]
        )
    }

    public func capture(_ event: CPUUsageEvent) {
        PostHogSDK.shared.capture(
            "cpu_usage",
            properties: [
                "player_type": event.playerType.rawValue,
                "cpu_usage": event.cpuUsage
            ]
        )
    }

    public func capture(_ event: CPUSessionEvent) {
        PostHogSDK.shared.capture(
            "cpu_session",
            properties: [
                "player_type": event.playerType.rawValue,
                "context": event.context.rawValue,
                "end_reason": event.endReason.rawValue,
                "average_cpu": event.averageCPU,
                "max_cpu": event.maxCPU,
                "sample_count": event.sampleCount,
                "duration_seconds": event.durationSeconds
            ]
        )
    }
}
