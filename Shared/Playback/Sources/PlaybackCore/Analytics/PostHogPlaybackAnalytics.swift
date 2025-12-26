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
        PostHogSDK.shared.capture(
            "playback_started",
            properties: [
                "reason": String(describing: event.reason)
            ]
        )
    }

    public func capture(_ event: PlaybackStoppedEvent) {
        var properties: [String: Any] = [
            "reason": String(describing: event.reason),
            "duration": event.duration
        ]

        // Extract error details if present
        if case .error(let playbackError) = event.reason {
            properties["error"] = String(describing: playbackError)
        }

        PostHogSDK.shared.capture(
            "playback_stopped",
            properties: properties
        )
    }

    public func capture(_ event: StallRecoveryEvent) {
        PostHogSDK.shared.capture(
            "stall_recovery",
            properties: [
                "attempts": event.attempts,
                "stall_duration": event.stallDuration
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
}
