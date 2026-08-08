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
    public static let resumeAfterRouteReconnect = PlaybackReason(rawValue: "resume after route reconnect")

    // Foreground/background
    public static let foregroundNotPlaying = PlaybackReason(rawValue: "foreground not playing")
    public static let foregroundToggle = PlaybackReason(rawValue: "foreground toggle")
    /// Playback was intended but not running when the app returned to the
    /// foreground (e.g. a session activation was deferred while backgrounded),
    /// so the stream is (re)started. See #514.
    public static let resumeAfterForeground = PlaybackReason(rawValue: "resume after foreground")

    // Watch/tvOS
    public static let watchPlayPause = PlaybackReason(rawValue: "Watch play/pause tapped")
    public static let tvOSCommand = PlaybackReason(rawValue: "tvOS command")

    // App entry points
    public static let carPlay = PlaybackReason(rawValue: "CarPlay")
    public static let quickAction = PlaybackReason(rawValue: "quick action")
    public static let deepLink = PlaybackReason(rawValue: "deep link")
    /// A replayed `INPlayMediaIntent` continuation — the launch-time SiriKit
    /// donation (`WXYCApp.makeSiriIntentInteraction()`) coming back through
    /// `NSUserActivity` continuation and foreground-launching the app.
    /// Despite the name it means only that, not "any Siri-originated play" —
    /// voice requests land on `.playIntent` / `.playAudioSchemaIntent`.
    ///
    /// **This series is empty in production, and a zero reading proves
    /// nothing.** Its sole call site is the third branch of
    /// `AppLifecycleModifier.handleUserActivity(_:)`, which is unreachable:
    /// that method is registered for exactly two activity types
    /// (`org.wxyc.iphoneapp.play` and `NSUserActivityTypeBrowsingWeb`), and
    /// the two branches ahead of it consume both. A real SiriKit replay
    /// arrives as activity type `INPlayMediaIntent`, which nothing registers
    /// for — even though `Info.plist` declares it under `NSUserActivityTypes`.
    /// Do not read this series as "no tile foreground-launched the app";
    /// see #830. Use `.mediaSuggestion` (#829) for tile-dispatch measurement.
    public static let siriIntent = PlaybackReason(rawValue: "Siri intent")
    /// A Handoff continuation from another device's WXYC app
    /// (`HandoffActivityManager`), distinct from `.quickAction` so a
    /// cross-device handoff is distinguishable in analytics.
    public static let handoff = PlaybackReason(rawValue: "handoff")

    // macOS in-app controls
    /// The macOS MenuBarExtra mini-player's play/pause control.
    public static let menuBar = PlaybackReason(rawValue: "menu bar")
    /// The macOS Dock right-click menu's play/pause item.
    public static let dockMenu = PlaybackReason(rawValue: "dock menu")

    // Intents
    public static let playIntent = PlaybackReason(rawValue: "PlayWXYC intent")
    public static let pauseIntent = PlaybackReason(rawValue: "PauseWXYC intent")
    public static let toggleIntent = PlaybackReason(rawValue: "ToggleWXYC intent")
    /// The iOS 27 audio-schema intent (`PlayWXYCAudio`). Distinct from `.playIntent`
    /// so PostHog can tell media-domain-routed plays from legacy `PlayWXYC` plays.
    public static let playAudioSchemaIntent = PlaybackReason(rawValue: "PlayWXYCAudio intent")
    /// A media-suggestion tile — the one iOS offers after headphones connect,
    /// dispatched as a background `INPlayMediaIntent` and serviced in-app by
    /// `PlayMediaIntentHandler` (no foreground launch). Distinct from
    /// `.siriIntent`, which is specifically the `NSUserActivity` continuation
    /// of a replayed donation and *requires* a foreground launch. See #829.
    public static let mediaSuggestion = PlaybackReason(rawValue: "media suggestion")
    /// WXYC's own widget-style UI — the Home Screen widget's Play/Pause
    /// button or the Control Center "Control Widget" toggle WXYC ships —
    /// routed through the dedicated `WidgetToggleWXYC` intent, distinct from
    /// `.toggleIntent` so Siri/Shortcuts invoking the shared `ToggleWXYC`
    /// action is no longer indistinguishable from a widget tap in analytics.
    /// See #668.
    public static let widgetToggle = PlaybackReason(rawValue: "widget toggle")

    // Testing
    public static let test = PlaybackReason(rawValue: "test")
    public static let testToggle = PlaybackReason(rawValue: "test toggle")
    public static let userTappedPlay = PlaybackReason(rawValue: "user tapped play")
    public static let userStartedStream = PlaybackReason(rawValue: "user started stream")
    public static let initial = PlaybackReason(rawValue: "initial")
    public static let errorHandlingTest = PlaybackReason(rawValue: "error handling test")
}
