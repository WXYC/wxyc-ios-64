//
//  ThemePickerState.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import Foundation
import Observation

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

import SwiftUI

public extension EnvironmentValues {
    var isThemePickerActive: Bool {
        get { self[ThemePickerActiveKey.self] }
        set { self[ThemePickerActiveKey.self] = newValue }
    }

    var wallpaperAnimationStartTime: Date {
        get { self[WallpaperAnimationStartTimeKey.self] }
        set { self[WallpaperAnimationStartTimeKey.self] = newValue }
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

    public init() {}

    // MARK: - Lifecycle

    /// Enters picker mode, centering on the currently selected theme.
    /// - Parameter currentThemeID: The currently selected theme ID to center on.
    public func enter(currentThemeID: String) {
        centeredThemeID = currentThemeID
        carouselIndex = indexFor(themeID: currentThemeID)
        isActive = true
    }

    /// Confirms the current centered theme as the selection.
    /// - Parameter configuration: The theme configuration to update.
    public func confirmSelection(to configuration: ThemeConfiguration) {
        configuration.selectedThemeID = centeredThemeID
    }

    /// Exits picker mode.
    public func exit() {
        isActive = false
    }

    // MARK: - Carousel Navigation

    /// Updates the centered theme based on carousel index.
    /// - Parameter index: The new carousel index.
    public func updateCenteredTheme(forIndex index: Int) {
        let themes = ThemeRegistry.shared.themes
        guard index >= 0 && index < themes.count else { return }
        carouselIndex = index
        centeredThemeID = themes[index].id
    }

    // MARK: - Private

    private func indexFor(themeID: String) -> Int {
        ThemeRegistry.shared.themes.firstIndex { $0.id == themeID } ?? 0
    }
}
