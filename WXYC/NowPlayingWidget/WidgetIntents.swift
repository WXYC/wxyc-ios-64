//
//  WidgetIntents.swift
//  NowPlayingWidget
//
//  Widget-specific App Intents that open the main app to control playback.
//  Widgets cannot play audio directly - they trigger the main app via intents.
//

import Foundation
import AppIntents
import Core

// MARK: - Widget Playback Intents

/// Intent to play WXYC - opens the app to start playback
struct PlayWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Plays WXYC"
    public static let isDiscoverable = true
    public static let openAppWhenRun = true  // Widget must open app to play audio
    public static let title: LocalizedStringResource = "Play WXYC"

    public init() { }
    
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // The actual playback will be handled by the main app when it opens
        return .result(value: "Tuning in to WXYC…")
    }
}

/// Intent to pause WXYC playback
struct PauseWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Pauses WXYC"
    public static let isDiscoverable = false
    public static let openAppWhenRun = true  // Widget must open app to pause
    public static let title: LocalizedStringResource = "Pause WXYC"

    public init() { }
    
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: "Pausing WXYC")
    }
}

/// Intent to toggle WXYC playback state
struct ToggleWXYC: AudioPlaybackIntent {
    public static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    public static let description = "Toggles WXYC Playback"
    public static let isDiscoverable = false
    public static let openAppWhenRun = true  // Widget must open app to toggle
    public static let title: LocalizedStringResource = "Toggle WXYC"

    public init() { }
    
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        return .result(value: "Toggling WXYC")
    }
}

extension PlayWXYC: ControlConfigurationIntent { }



