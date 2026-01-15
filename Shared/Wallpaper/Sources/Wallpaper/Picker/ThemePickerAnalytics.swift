//
//  ThemePickerAnalytics.swift
//  Wallpaper
//
//  Analytics protocol for theme picker events.
//
//  Created by Jake Bromberg on 01/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Analytics

// MARK: - Event Types

/// Event when user enters theme picker mode.
public struct ThemePickerEnteredEvent: AnalyticsEvent {
    public let name = "theme_picker_entered"

    public let fromThemeID: String
    public let timestamp: Date
    
    public var properties: [String: Any]? {
        [
            "from_theme_id": fromThemeID,
            "timestamp": timestamp.timeIntervalSince1970
        ]
    }

    public init(fromThemeID: String, timestamp: Date = Date()) {
        self.fromThemeID = fromThemeID
        self.timestamp = timestamp
    }
}

/// Event when user confirms a theme selection.
public struct ThemePickerSelectionEvent: AnalyticsEvent {
    public let name = "theme_picker_selection"

    public let selectedThemeID: String
    public let previousThemeID: String
    public let themeChanged: Bool
    public let durationSeconds: TimeInterval
    
    public var properties: [String: Any]? {
        [
            "selected_theme_id": selectedThemeID,
            "previous_theme_id": previousThemeID,
            "theme_changed": themeChanged,
            "duration_seconds": durationSeconds
        ]
    }

    public init(
        selectedThemeID: String,
        previousThemeID: String,
        themeChanged: Bool,
        durationSeconds: TimeInterval
    ) {
        self.selectedThemeID = selectedThemeID
        self.previousThemeID = previousThemeID
        self.themeChanged = themeChanged
        self.durationSeconds = durationSeconds
    }
}

/// Event when user dismisses the theme tip.
public struct ThemeTipDismissedEvent: AnalyticsEvent {
    public let name = "theme_tip_dismissed"
    
    public let hadEverEnteredPicker: Bool
    
    public var properties: [String: Any]? {
        ["had_ever_entered_picker": hadEverEnteredPicker]
    }

    public init(hadEverEnteredPicker: Bool) {
        self.hadEverEnteredPicker = hadEverEnteredPicker
    }
}

// MARK: - ThemePickerAnalytics Protocol

/// Protocol for theme picker analytics.
///
/// Implementations capture events to analytics backends.
/// The Wallpaper package defines this protocol; the app layer provides
/// the concrete implementation (e.g., PostHog).
@MainActor
@available(*, deprecated, message: "Use AnalyticsService instead")
public protocol ThemePickerAnalytics: AnyObject {
    /// Records when user enters theme picker mode.
    func record(_ event: ThemePickerEnteredEvent)

    /// Records when user confirms a theme selection.
    func record(_ event: ThemePickerSelectionEvent)

    /// Records when user dismisses the theme tip.
    func record(_ event: ThemeTipDismissedEvent)
}
