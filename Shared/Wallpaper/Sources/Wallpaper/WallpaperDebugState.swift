//
//  WallpaperDebugState.swift
//  Wallpaper
//
//  Manages state for the theme debug overlay.
//

import Foundation
import Observation

/// State for the theme debug overlay button visibility.
@Observable
@MainActor
public final class ThemeDebugState {
    public static let shared = ThemeDebugState()

    private let storageKey = "wallpaper.debug.showOverlay"

    public var showOverlay: Bool {
        didSet {
            UserDefaults.standard.set(showOverlay, forKey: storageKey)
        }
    }

    private init() {
        self.showOverlay = UserDefaults.standard.bool(forKey: storageKey)
    }
}
