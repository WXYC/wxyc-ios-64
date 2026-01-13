//
//  ThemePickerPersistence.swift
//  Wallpaper
//

import Caching
import Foundation

/// Persistence layer for theme picker state.
///
/// Tracks whether the user has ever used the picker and when the tip was dismissed.
/// Inject via `ThemePickerState.setPersistence()` for testability.
@MainActor
public final class ThemePickerPersistence: Sendable {

    // MARK: - Configuration

    /// Number of days before re-showing the tip to users who dismissed without using the picker.
    public static let reShowCooldownDays: TimeInterval = 90

    // MARK: - Keys

    private enum Keys {
        static let hasEverUsedPicker = "themePicker.hasEverBeenUsed"
        static let tipDismissedAt = "themeTip.dismissedAt"
    }

    // MARK: - Storage

    private let defaults: DefaultsStorage

    // MARK: - Initialization

    /// Creates a persistence instance with the specified defaults storage.
    ///
    /// - Parameter defaults: The storage instance to use for persistence.
    public init(defaults: DefaultsStorage = UserDefaults.standard) {
        self.defaults = defaults
    }

    // MARK: - Picker Usage

    /// Whether the user has ever entered the theme picker.
    public var hasEverUsedPicker: Bool {
        defaults.bool(forKey: Keys.hasEverUsedPicker)
    }

    /// Records that the user has used the picker.
    ///
    /// This is idempotent - subsequent calls have no effect.
    public func recordPickerUsed() {
        guard !hasEverUsedPicker else { return }
        defaults.set(true, forKey: Keys.hasEverUsedPicker)
    }

    // MARK: - Tip Visibility

    /// Whether the theme tip should be shown.
    ///
    /// Returns true if:
    /// - User has never used the picker AND
    /// - (Tip was never dismissed OR tip was dismissed 90+ days ago)
    public var shouldShowTip: Bool {
        // If user has used the picker, never show the tip
        if hasEverUsedPicker {
            return false
        }

        // If never dismissed, show it
        guard let dismissedAt = defaults.object(forKey: Keys.tipDismissedAt) as? Date else {
            return true
        }

        // Re-show after cooldown period if user still hasn't used the picker
        let daysSinceDismissal = Date().timeIntervalSince(dismissedAt) / 86400
        return daysSinceDismissal >= Self.reShowCooldownDays
    }

    /// When the tip was last dismissed, if ever.
    public var tipDismissedAt: Date? {
        defaults.object(forKey: Keys.tipDismissedAt) as? Date
    }

    /// Records that the tip was dismissed.
    public func recordTipDismissed() {
        defaults.set(Date(), forKey: Keys.tipDismissedAt)
    }

    // MARK: - Reset

    /// Resets all persistence state (for testing via debug panel).
    public func resetState() {
        defaults.removeObject(forKey: Keys.hasEverUsedPicker)
        defaults.removeObject(forKey: Keys.tipDismissedAt)
    }
}
