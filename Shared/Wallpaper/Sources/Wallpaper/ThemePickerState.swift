//
//  ThemePickerState.swift
//  Wallpaper
//
//  Observable state for theme picker UI.
//
//  Created by Jake Bromberg on 12/21/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Logger
import Observation
import SwiftUI
import Analytics

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

/// Environment key for the wallpaper-derived mesh gradient palette.
/// When set, AnimatedMeshGradient uses these colors instead of random colors.
private struct WallpaperMeshGradientPaletteKey: EnvironmentKey {
    static let defaultValue: [Color]? = nil
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

    /// The wallpaper-derived mesh gradient palette (16 colors).
    /// When nil, AnimatedMeshGradient uses random colors.
    var wallpaperMeshGradientPalette: [Color]? {
        get { self[WallpaperMeshGradientPaletteKey.self] }
        set { self[WallpaperMeshGradientPaletteKey.self] = newValue }
    }
}

/// Observable state for the theme picker mode.
/// Manages the picker lifecycle and carousel position.
@MainActor
@Observable
public final class ThemePickerState {
    /// The shared animation used for all theme picker transitions.
    /// Use this with `withAnimation` at state change sites to ensure
    /// all views animate together via SwiftUI's transaction system.
    public static let transitionAnimation: Animation = .spring(duration: 0.5, bounce: 0.2)

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
    private var analytics: AnalyticsService?

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
    public func setAnalytics(_ analytics: AnalyticsService) {
        self.analytics = analytics
    }

    /// Records that the user dismissed the theme tip via the close button.
    ///
    /// This records both analytics and persistence. For auto-dismissal
    /// (when user enters the picker), use `enter(currentThemeID:)` instead.
    public func recordTipDismissedByUser() {
        analytics?.capture(ThemeTipDismissedEvent(
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
        analytics?.capture(ThemePickerEnteredEvent(fromThemeID: currentThemeID))
    }

    /// Confirms the current centered theme as the selection and records analytics.
    /// - Parameter configuration: The theme configuration to update.
    public func confirmSelection(to configuration: ThemeConfiguration) {
        let selectedThemeID = centeredThemeID
        let previousID = previousThemeID ?? configuration.selectedThemeID
        let themeChanged = selectedThemeID != previousID
        let duration = enteredAt.map { Date().timeIntervalSince($0) } ?? 0

        configuration.selectedThemeID = selectedThemeID

        // Log theme selection
        if themeChanged {
            Log(.info, category: .wallpaper, "Theme changed from '\(previousID)' to '\(selectedThemeID)'")
        } else {
            Log(.info, category: .wallpaper, "Theme confirmed: '\(selectedThemeID)' (unchanged)")
        }

        // Record analytics event
        analytics?.capture(ThemePickerSelectionEvent(
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
