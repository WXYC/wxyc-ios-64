//
//  SiriTipView.swift
//  WXYC
//
//  Siri tip callout for voice control.
//
//  Created by Jake Bromberg on 12/04/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Caching
import SwiftUI
import Wallpaper
import WXUI

/// A custom Siri tip view that displays a suggestion to use voice commands.
///
/// Display Logic:
/// Shows after the second launch, until dismissed; never shows again once dismissed.
/// Use the debug panel to reset tip state for testing.
struct SiriTipView: View {
    @Binding var isVisible: Bool
    private let onDismiss: () -> Void

    init(isVisible: Binding<Bool>, onDismiss: @escaping () -> Void = { }) {
        self._isVisible = isVisible
        self.onDismiss = onDismiss
    }

    var body: some View {
        TipView(
            iconName: "siri",
            caption: "Try saying",
            headline: "\u{201C}Hey Siri, play WXYC\u{201D}",
            isVisible: $isVisible,
            onDismiss: onDismiss
        ) {
            BackgroundLayer(cornerRadius: 16)
        }
    }
}

// MARK: - Persistence

extension SiriTipView {
    private static let hasLaunchedBeforeKey = "siriTip.hasLaunchedBefore"
    private static let wasDismissedKey = "siriTip.wasDismissed"

    /// Call this at app launch to record that a launch has occurred.
    /// Returns whether the Siri tip should be shown.
    static func recordLaunchAndShouldShow(defaults: DefaultsStorage = UserDefaults.standard) -> Bool {
        // If user already dismissed, never show again
        if defaults.bool(forKey: wasDismissedKey) {
            return false
        }

        // Check if this is the first launch
        let hasLaunchedBefore = defaults.bool(forKey: hasLaunchedBeforeKey)

        if !hasLaunchedBefore {
            // First launch - record it but don't show the tip
            defaults.set(true, forKey: hasLaunchedBeforeKey)
            return false
        }

        // Second launch or later, and not yet dismissed - show the tip
        return true
    }

    /// Call this when the user dismisses the tip to prevent future displays.
    static func recordDismissal(defaults: DefaultsStorage = UserDefaults.standard) {
        defaults.set(true, forKey: wasDismissedKey)
    }

    /// Resets the Siri tip state (useful for testing).
    static func resetState(defaults: DefaultsStorage = UserDefaults.standard) {
        defaults.removeObject(forKey: hasLaunchedBeforeKey)
        defaults.removeObject(forKey: wasDismissedKey)
    }
}
