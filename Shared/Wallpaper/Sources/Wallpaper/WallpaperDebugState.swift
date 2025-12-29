//
//  WallpaperDebugState.swift
//  Wallpaper
//
//  Manages state for the wallpaper debug overlay.
//

import Foundation
import Observation

/// State for the wallpaper debug overlay button visibility.
@Observable
@MainActor
public final class WallpaperDebugState {
    public static let shared = WallpaperDebugState()

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
