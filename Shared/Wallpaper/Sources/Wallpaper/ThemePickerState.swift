//
//  ThemePickerState.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Theme Transition

/// Represents an in-progress transition between two themes during picker scrolling.
@MainActor
public struct ThemeTransition: Equatable {
    public let fromTheme: LoadedTheme
    public let toTheme: LoadedTheme
    /// Progress from 0.0 (fully fromTheme) to 1.0 (fully toTheme).
    public let progress: CGFloat

    public init(fromTheme: LoadedTheme, toTheme: LoadedTheme, progress: CGFloat) {
        self.fromTheme = fromTheme
        self.toTheme = toTheme
        self.progress = progress
    }

    public var fromMaterial: Material { fromTheme.manifest.materialWeight.material }
    public var toMaterial: Material { toTheme.manifest.materialWeight.material }
    public var fromColorScheme: ColorScheme { fromTheme.manifest.foreground.colorScheme }
    public var toColorScheme: ColorScheme { toTheme.manifest.foreground.colorScheme }
    public var fromMaterialTint: Double { fromTheme.manifest.materialTint }
    public var toMaterialTint: Double { toTheme.manifest.materialTint }

    /// Interpolated tint value based on transition progress.
    public var interpolatedMaterialTint: Double {
        fromMaterialTint + (toMaterialTint - fromMaterialTint) * progress
    }

    // MARK: Accent Color

    public var fromAccent: AccentColor { fromTheme.manifest.accent }
    public var toAccent: AccentColor { toTheme.manifest.accent }

    /// Interpolated accent hue (normalized 0.0-1.0) based on transition progress.
    public var interpolatedAccentHue: Double {
        let fromHue = fromAccent.normalizedHue
        let toHue = toAccent.normalizedHue
        return fromHue + (toHue - fromHue) * progress
    }

    /// Interpolated accent saturation based on transition progress.
    public var interpolatedAccentSaturation: Double {
        let fromSat = fromAccent.saturation
        let toSat = toAccent.saturation
        return fromSat + (toSat - fromSat) * progress
    }

    public static nonisolated func == (lhs: ThemeTransition, rhs: ThemeTransition) -> Bool {
        lhs.fromTheme.id == rhs.fromTheme.id &&
        lhs.toTheme.id == rhs.toTheme.id &&
        lhs.progress == rhs.progress
    }
}

// MARK: - Environment Key

/// Environment key to indicate whether the theme picker is active.
/// Content can use this to adjust layout (e.g., disable safe area padding when scaled).
private struct ThemePickerActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

/// Environment key for the shared wallpaper animation start time.
/// All wallpaper renderers use this to stay synchronized.
private struct WallpaperAnimationStartTimeKey: EnvironmentKey {
    static let defaultValue: Date = Date()
}

/// Environment key for a fixed quality profile that overrides adaptive thermal optimization.
private struct WallpaperQualityProfileKey: EnvironmentKey {
    static let defaultValue: QualityProfile? = nil
}

/// Environment key for the current theme transition during picker scrolling.
private struct PreviewThemeTransitionKey: EnvironmentKey {
    static let defaultValue: ThemeTransition? = nil
}

/// Environment key for the current theme's material tint value.
private struct CurrentMaterialTintKey: EnvironmentKey {
    static let defaultValue: Double = 0.0
}

/// Environment key for the current theme's material.
private struct CurrentMaterialKey: EnvironmentKey {
    static let defaultValue: Material = .thinMaterial
}

/// Environment key for the current/interpolated accent hue (normalized 0.0-1.0).
private struct CurrentAccentHueKey: EnvironmentKey {
    static let defaultValue: Double = 23.0 / 360.0 // Default orange
}

/// Environment key for the current/interpolated accent saturation.
private struct CurrentAccentSaturationKey: EnvironmentKey {
    static let defaultValue: Double = 0.75
}

public extension EnvironmentValues {
    var isThemePickerActive: Bool {
        get { self[ThemePickerActiveKey.self] }
        set { self[ThemePickerActiveKey.self] = newValue }
    }

    var wallpaperAnimationStartTime: Date {
        get { self[WallpaperAnimationStartTimeKey.self] }
        set { self[WallpaperAnimationStartTimeKey.self] = newValue }
    }

    /// Optional quality profile that overrides adaptive thermal optimization.
    ///
    /// When set, renderers use these fixed FPS and scale values instead of
    /// the adaptive thermal controller. Use for contexts like the wallpaper
    /// picker where lower quality is acceptable.
    var wallpaperQualityProfile: QualityProfile? {
        get { self[WallpaperQualityProfileKey.self] }
        set { self[WallpaperQualityProfileKey.self] = newValue }
    }

    /// Theme transition state for preview during picker scrolling.
    var previewThemeTransition: ThemeTransition? {
        get { self[PreviewThemeTransitionKey.self] }
        set { self[PreviewThemeTransitionKey.self] = newValue }
    }

    /// The current theme's material tint value for non-picker mode.
    var currentMaterialTint: Double {
        get { self[CurrentMaterialTintKey.self] }
        set { self[CurrentMaterialTintKey.self] = newValue }
    }

    /// The current theme's material for non-picker mode.
    var currentMaterial: Material {
        get { self[CurrentMaterialKey.self] }
        set { self[CurrentMaterialKey.self] = newValue }
    }

    /// The current/interpolated accent hue (normalized 0.0-1.0).
    var currentAccentHue: Double {
        get { self[CurrentAccentHueKey.self] }
        set { self[CurrentAccentHueKey.self] = newValue }
    }

    /// The current/interpolated accent saturation.
    var currentAccentSaturation: Double {
        get { self[CurrentAccentSaturationKey.self] }
        set { self[CurrentAccentSaturationKey.self] = newValue }
    }
}

/// Observable state for the theme picker mode.
/// Manages the picker lifecycle and carousel position.
@MainActor
@Observable
public final class ThemePickerState {
    /// Whether the picker mode is currently active.
    public var isActive: Bool = false

    /// The theme ID currently centered in the carousel.
    /// This may differ from the selected theme until the user confirms.
    public var centeredThemeID: String = ""

    /// The carousel page index (corresponds to theme position in registry).
    public var carouselIndex: Int = 0

    /// Current theme transition state during picker scrolling.
    public private(set) var themeTransition: ThemeTransition?

    // MARK: - Dependencies

    /// Theme registry for looking up themes.
    private let registry: any ThemeRegistryProtocol

    /// Analytics handler for theme picker events.
    private var analytics: ThemePickerAnalytics?

    /// Persistence layer for picker state.
    public var persistence = ThemePickerPersistence()

    /// When the picker was entered (for duration tracking).
    private var enteredAt: Date?

    /// Theme ID when picker was entered (for change detection).
    private var previousThemeID: String?

    /// Creates a picker state with injected dependencies.
    /// - Parameter registry: The theme registry for looking up themes.
    public init(registry: any ThemeRegistryProtocol = ThemeRegistry.shared) {
        self.registry = registry
    }

    /// Sets the analytics handler for theme picker events.
    ///
    /// - Parameter analytics: The analytics implementation to use.
    public func setAnalytics(_ analytics: ThemePickerAnalytics) {
        self.analytics = analytics
    }

    /// Records that the user dismissed the theme tip via the close button.
    ///
    /// This records both analytics and persistence. For auto-dismissal
    /// (when user enters the picker), use `enter(currentThemeID:)` instead.
    public func recordTipDismissedByUser() {
        analytics?.record(ThemeTipDismissedEvent(
            hadEverEnteredPicker: persistence.hasEverUsedPicker
        ))
        persistence.recordTipDismissed()
    }

    // MARK: - Lifecycle

    /// Enters picker mode, centering on the currently selected theme.
    /// - Parameter currentThemeID: The currently selected theme ID to center on.
    public func enter(currentThemeID: String) {
        centeredThemeID = currentThemeID
        carouselIndex = indexFor(themeID: currentThemeID)
        isActive = true

        // Track for analytics
        enteredAt = Date()
        previousThemeID = currentThemeID

        // Record first-time usage for discoverability tracking
        persistence.recordPickerUsed()

        // Auto-dismiss the theme tip since user discovered the picker
        persistence.recordTipDismissed()

        // Record analytics event
        analytics?.record(ThemePickerEnteredEvent(fromThemeID: currentThemeID))
    }

    /// Confirms the current centered theme as the selection and records analytics.
    /// - Parameter configuration: The theme configuration to update.
    public func confirmSelection(to configuration: ThemeConfiguration) {
        let selectedThemeID = centeredThemeID
        let previousID = previousThemeID ?? configuration.selectedThemeID
        let themeChanged = selectedThemeID != previousID
        let duration = enteredAt.map { Date().timeIntervalSince($0) } ?? 0

        configuration.selectedThemeID = selectedThemeID

        // Record analytics event
        analytics?.record(ThemePickerSelectionEvent(
            selectedThemeID: selectedThemeID,
            previousThemeID: previousID,
            themeChanged: themeChanged,
            durationSeconds: duration
        ))
    }

    /// Exits picker mode.
    public func exit() {
        isActive = false
        themeTransition = nil
        enteredAt = nil
        previousThemeID = nil
    }

    // MARK: - Carousel Navigation

    /// Updates the centered theme based on carousel index.
    /// - Parameter index: The new carousel index.
    public func updateCenteredTheme(forIndex index: Int) {
        let themes = registry.themes
        guard index >= 0 && index < themes.count else { return }
        carouselIndex = index
        centeredThemeID = themes[index].id
    }

    /// Updates the transition progress based on continuous scroll offset.
    /// - Parameters:
    ///   - scrollOffset: The current horizontal scroll offset.
    ///   - cardWidth: The width of each card.
    ///   - cardSpacing: The spacing between cards.
    ///   - horizontalPadding: The horizontal padding applied to center the first card.
    public func updateTransitionProgress(
        scrollOffset: CGFloat,
        cardWidth: CGFloat,
        cardSpacing: CGFloat,
        horizontalPadding: CGFloat
    ) {
        let themes = registry.themes
        guard themes.count > 1 else {
            themeTransition = nil
            return
        }

        let effectiveOffset = scrollOffset + horizontalPadding
        let cardTotalWidth = cardWidth + cardSpacing
        let currentPosition = effectiveOffset / cardTotalWidth

        let leadingIndex = max(0, min(themes.count - 2, Int(floor(currentPosition))))
        let trailingIndex = min(themes.count - 1, leadingIndex + 1)
        let progress = max(0, min(1, currentPosition - CGFloat(leadingIndex)))

        themeTransition = ThemeTransition(
            fromTheme: themes[leadingIndex],
            toTheme: themes[trailingIndex],
            progress: progress
        )
    }

    // MARK: - Private

    private func indexFor(themeID: String) -> Int {
        registry.themes.firstIndex { $0.id == themeID } ?? 0
    }
}
