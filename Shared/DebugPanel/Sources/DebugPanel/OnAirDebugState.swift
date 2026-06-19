//
//  OnAirDebugState.swift
//  DebugPanel
//
//  Observable singleton for forcing the playlist "on air" banner to display during testing.
//
//  Created by Jake Bromberg on 06/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Shared debug state for forcing the playlist "on air" banner to display.
///
/// Lets you preview the banner between DJs, when no sign-on is present in the flowsheet.
@MainActor
@Observable
public final class OnAirDebugState {
    public static let shared = OnAirDebugState()

    /// When true, the playlist shows the on-air banner with a placeholder DJ even when
    /// no one is currently signed on.
    public var forceOnAir: Bool {
        didSet {
            UserDefaults.standard.set(forceOnAir, forKey: "OnAirDebug.forceOnAir")
        }
    }

    private init() {
        self.forceOnAir = UserDefaults.standard.bool(forKey: "OnAirDebug.forceOnAir")
    }
}
