//
//  PlaybackReason.swift
//  PlaybackCore
//
//  A type-safe reason for playback state changes, used for analytics.
//  Modules extend this struct to define their own domain-specific reasons.
//
//  Created by Claude on 01/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A type-safe reason for playback state changes.
///
/// This struct provides type safety for analytics tracking while allowing
/// each module to define its own domain-specific reasons via extensions.
///
/// Example:
/// ```swift
/// // In your module
/// extension PlaybackReason {
///     static let userTappedPlay = PlaybackReason(rawValue: "user tapped play")
/// }
/// ```
public struct PlaybackReason: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String {
        rawValue
    }
}

// MARK: - Core Reasons

extension PlaybackReason {
    // Remote command center
    public static let remotePlayCommand = PlaybackReason(rawValue: "remote play command")
    public static let remotePauseCommand = PlaybackReason(rawValue: "remote pause command")
    public static let remoteToggleCommand = PlaybackReason(rawValue: "remote toggle command")

    // System interruptions
    public static let interruptionBegan = PlaybackReason(rawValue: "interruption began")
    public static let resumeAfterInterruption = PlaybackReason(rawValue: "resume after interruption")

    // Route changes
    public static let routeDisconnected = PlaybackReason(rawValue: "route disconnected")

    // Foreground/background
    public static let foregroundNotPlaying = PlaybackReason(rawValue: "foreground not playing")
    public static let foregroundToggle = PlaybackReason(rawValue: "foreground toggle")

    // Watch/tvOS
    public static let watchPlayPause = PlaybackReason(rawValue: "Watch play/pause tapped")
    public static let tvOSCommand = PlaybackReason(rawValue: "tvOS command")

    // App entry points
    public static let carPlay = PlaybackReason(rawValue: "CarPlay")
    public static let quickAction = PlaybackReason(rawValue: "quick action")
    public static let deepLink = PlaybackReason(rawValue: "deep link")
    public static let siriIntent = PlaybackReason(rawValue: "Siri intent")

    // Intents
    public static let playIntent = PlaybackReason(rawValue: "PlayWXYC intent")
    public static let pauseIntent = PlaybackReason(rawValue: "PauseWXYC intent")
    public static let toggleIntent = PlaybackReason(rawValue: "ToggleWXYC intent")

    // Testing
    public static let test = PlaybackReason(rawValue: "test")
    public static let testToggle = PlaybackReason(rawValue: "test toggle")
    public static let userTappedPlay = PlaybackReason(rawValue: "user tapped play")
    public static let userStartedStream = PlaybackReason(rawValue: "user started stream")
    public static let initial = PlaybackReason(rawValue: "initial")
    public static let errorHandlingTest = PlaybackReason(rawValue: "error handling test")
}
