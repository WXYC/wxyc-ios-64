//
//  ThemePickerAnalytics.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 1/6/26.
//

import Foundation

// MARK: - Event Types

/// Event when user enters theme picker mode.
public struct ThemePickerEnteredEvent: Sendable {
    public let fromThemeID: String
    public let timestamp: Date

    public init(fromThemeID: String, timestamp: Date = Date()) {
        self.fromThemeID = fromThemeID
        self.timestamp = timestamp
    }
}

/// Event when user confirms a theme selection.
public struct ThemePickerSelectionEvent: Sendable {
    public let selectedThemeID: String
    public let previousThemeID: String
    public let themeChanged: Bool
    public let durationSeconds: TimeInterval

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
public struct ThemeTipDismissedEvent: Sendable {
    public let hadEverEnteredPicker: Bool

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
public protocol ThemePickerAnalytics: AnyObject {
    /// Records when user enters theme picker mode.
    func record(_ event: ThemePickerEnteredEvent)

    /// Records when user confirms a theme selection.
    func record(_ event: ThemePickerSelectionEvent)

    /// Records when user dismisses the theme tip.
    func record(_ event: ThemeTipDismissedEvent)
}

// MARK: - Picker Usage Tracking

/// Tracks whether the user has ever used the theme picker.
///
/// Used for discoverability analytics and to auto-dismiss the theme tip.
public enum ThemePickerUsage {
    private static let key = "themePicker.hasEverBeenUsed"

    /// Whether the user has ever entered the theme picker.
    public static var hasEverUsed: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    /// Records that the user has used the picker for the first time.
    public static func recordFirstUse() {
        guard !hasEverUsed else { return }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Resets the usage state (for testing via debug panel).
    public static func resetState() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

