//
//  WallpaperPickerState.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import Foundation
import Observation

// MARK: - Environment Key

/// Environment key to indicate whether the wallpaper picker is active.
/// Content can use this to adjust layout (e.g., disable safe area padding when scaled).
private struct WallpaperPickerActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

/// Environment key for the shared wallpaper animation start time.
/// All wallpaper renderers use this to stay synchronized.
private struct WallpaperAnimationStartTimeKey: EnvironmentKey {
    static let defaultValue: Date = Date()
}

import SwiftUI

public extension EnvironmentValues {
    var isWallpaperPickerActive: Bool {
        get { self[WallpaperPickerActiveKey.self] }
        set { self[WallpaperPickerActiveKey.self] = newValue }
    }

    var wallpaperAnimationStartTime: Date {
        get { self[WallpaperAnimationStartTimeKey.self] }
        set { self[WallpaperAnimationStartTimeKey.self] = newValue }
    }
}

/// Observable state for the wallpaper picker mode.
/// Manages the picker lifecycle and carousel position.
@MainActor
@Observable
public final class WallpaperPickerState {
    /// Whether the picker mode is currently active.
    public var isActive: Bool = false

    /// The wallpaper ID currently centered in the carousel.
    /// This may differ from the selected wallpaper until the user confirms.
    public var centeredWallpaperID: String = ""

    /// The carousel page index (corresponds to wallpaper position in registry).
    public var carouselIndex: Int = 0

    public init() {}

    // MARK: - Lifecycle

    /// Enters picker mode, centering on the currently selected wallpaper.
    /// - Parameter currentWallpaperID: The currently selected wallpaper ID to center on.
    public func enter(currentWallpaperID: String) {
        centeredWallpaperID = currentWallpaperID
        carouselIndex = indexFor(wallpaperID: currentWallpaperID)
        isActive = true
    }

    /// Confirms the current centered wallpaper as the selection.
    /// - Parameter configuration: The wallpaper configuration to update.
    public func confirmSelection(to configuration: WallpaperConfiguration) {
        configuration.selectedWallpaperID = centeredWallpaperID
    }

    /// Exits picker mode.
    public func exit() {
        isActive = false
    }

    // MARK: - Carousel Navigation

    /// Updates the centered wallpaper based on carousel index.
    /// - Parameter index: The new carousel index.
    public func updateCenteredWallpaper(forIndex index: Int) {
        let wallpapers = WallpaperRegistry.shared.wallpapers
        guard index >= 0 && index < wallpapers.count else { return }
        carouselIndex = index
        centeredWallpaperID = wallpapers[index].id
    }

    // MARK: - Private

    private func indexFor(wallpaperID: String) -> Int {
        WallpaperRegistry.shared.wallpapers.firstIndex { $0.id == wallpaperID } ?? 0
    }
}
