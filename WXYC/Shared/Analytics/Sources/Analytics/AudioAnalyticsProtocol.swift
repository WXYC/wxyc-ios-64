//
//  AudioAnalyticsProtocol.swift
//  Analytics
//
//  Protocol for analytics reporting in audio playback
//

import Foundation
import PostHog

/// Protocol for analytics reporting during audio playback
/// Implementations can integrate with PostHog, Firebase, or other analytics services
public protocol AudioAnalyticsProtocol: AnyObject {
    /// Called when playback starts
    /// - Parameters:
    ///   - source: The source of the play action (e.g., function name)
    ///   - reason: Human-readable reason for starting playback
    func play(source: String, reason: String)
    
    /// Called when playback pauses
    /// - Parameters:
    ///   - source: The source of the pause action
    ///   - duration: How long playback lasted before pausing
    func pause(source: String, duration: TimeInterval)
    
    /// Called when playback pauses with a specific reason
    /// - Parameters:
    ///   - source: The source of the pause action
    ///   - duration: How long playback lasted before pausing
    ///   - reason: Human-readable reason for pausing
    func pause(source: String, duration: TimeInterval, reason: String)
    
    /// Called when an error occurs during playback
    /// - Parameters:
    ///   - error: The error that occurred
    ///   - context: Context describing where/when the error occurred
    func capture(error: Error, context: String)
}

/// Default implementations for convenience
public extension AudioAnalyticsProtocol {
    /// Pause without a specific reason
    func pause(source: String, duration: TimeInterval) {
        pause(source: source, duration: duration, reason: "")
    }
}

// MARK: - PostHogSDK Conformance

extension PostHogSDK: AudioAnalyticsProtocol {
    public func play(source: String, reason: String) {
        capture(
            "play",
            properties: [
                "source": source,
                "reason": reason,
            ]
        )
    }
    
    public func pause(source: String, duration: TimeInterval) {
        capture(
            "pause",
            properties: [
                "source": source,
                "duration": duration,
            ]
        )
    }
    
    public func pause(source: String, duration: TimeInterval, reason: String) {
        capture(
            "pause",
            properties: [
                "source": source,
                "duration": duration,
                "reason": reason,
            ]
        )
    }
    
    public func capture(error: Error, context: String) {
        capture(
            "error",
            properties: [
                "description": "\(error.localizedDescription)",
                "context": context,
            ]
        )
    }
}

