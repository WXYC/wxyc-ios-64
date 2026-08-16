//
//  ThemeCycling.swift
//  WXYC
//
//  One-step theme navigation shared by the Themes command menu's arrow keys and
//  its j/k shortcuts. Stepping wraps at both ends of the registry, and where the
//  step lands depends on the picker: open, it moves the carousel and waits for a
//  confirm; closed, it commits the new theme immediately.
//
//  Created by Jake Bromberg on 08/16/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper

enum ThemeCycling {

    /// Which way a single step moves through the registry.
    enum Direction {
        case next
        case previous
    }

    /// The theme one step from `currentID`, wrapping around both ends of the list.
    ///
    /// - Parameters:
    ///   - currentID: The theme to step away from. An ID absent from `themeIDs`
    ///     (a renamed manifest, a stale stored value) lands on the near end of
    ///     the list rather than nowhere — the user is on an unrenderable theme
    ///     and a keypress should rescue them from it.
    ///   - themeIDs: Every available theme ID, in registry order.
    ///   - direction: Which way to step.
    /// - Returns: The destination theme ID, or `nil` when there is nowhere to
    ///   go (fewer than two themes).
    static func themeID(
        after currentID: String,
        in themeIDs: [String],
        direction: Direction
    ) -> String? {
        guard themeIDs.count > 1 else { return nil }

        guard let currentIndex = themeIDs.firstIndex(of: currentID) else {
            return direction == .next ? themeIDs.first : themeIDs.last
        }

        let step = direction == .next ? 1 : -1
        let destination = (currentIndex + step + themeIDs.count) % themeIDs.count
        return themeIDs[destination]
    }

    /// Moves theme selection one step in `direction`.
    ///
    /// With the picker open the step only scrolls the carousel, leaving the
    /// commit to `ThemePickerState.confirmSelection(to:)` as a swipe would. With
    /// the picker closed the step applies to `configuration` directly and
    /// unanimated, which is the whole point of the j/k shortcuts.
    ///
    /// - Returns: The theme now showing, or `nil` if there was nowhere to step.
    @MainActor
    @discardableResult
    static func cycle(
        _ direction: Direction,
        configuration: ThemeConfiguration,
        pickerState: ThemePickerState,
        registry: any ThemeRegistryProtocol = ThemeRegistry.shared
    ) -> String? {
        let themes = registry.themes
        // The picker's centered theme is the user's live position while it is
        // open; `selectedThemeID` still points at what they entered from.
        let currentID = pickerState.isActive ? pickerState.centeredThemeID : configuration.selectedThemeID

        guard let destinationID = themeID(
            after: currentID,
            in: themes.map(\.id),
            direction: direction
        ) else {
            return nil
        }

        if pickerState.isActive {
            guard let index = themes.firstIndex(where: { $0.id == destinationID }) else { return nil }
            withAnimation(.spring(duration: 0.3)) {
                pickerState.updateCenteredTheme(forIndex: index)
            }
        } else {
            configuration.selectedThemeID = destinationID
        }

        return destinationID
    }
}
