//
//  PostHogThemePickerAnalytics.swift
//  WXYC
//
//  PostHog implementation for theme picker analytics.
//
//  Created by Jake Bromberg on 01/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PostHog
import Wallpaper

/// Reports theme picker events to PostHog.
@MainActor
final class PostHogThemePickerAnalytics: ThemePickerAnalytics {

    init() {}

    func record(_ event: ThemePickerEnteredEvent) {
        PostHogSDK.shared.capture("theme_picker_entered", properties: [
            "from_theme_id": event.fromThemeID
        ])
    }

    func record(_ event: ThemePickerSelectionEvent) {
        PostHogSDK.shared.capture("theme_picker_selection", properties: [
            "selected_theme_id": event.selectedThemeID,
            "previous_theme_id": event.previousThemeID,
            "theme_changed": event.themeChanged,
            "duration_seconds": event.durationSeconds
        ])
    }

    func record(_ event: ThemeTipDismissedEvent) {
        PostHogSDK.shared.capture("theme_tip_dismissed", properties: [
            "had_ever_entered_picker": event.hadEverEnteredPicker
        ])
    }
}
