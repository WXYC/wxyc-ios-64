//
//  DebugHUDState.swift
//  DebugPanel
//
//  Created by Jake Bromberg on 12/23/25.
//

import Foundation

/// Shared state for the debug HUD visibility.
@MainActor
@Observable
public final class DebugHUDState {
    public static let shared = DebugHUDState()

    public var isVisible: Bool {
        didSet {
            UserDefaults.standard.set(isVisible, forKey: "DebugHUD.isVisible")
        }
    }

    private init() {
        self.isVisible = UserDefaults.standard.bool(forKey: "DebugHUD.isVisible")
    }
}
