//
//  ForegroundTransition.swift
//  AppServices
//
//  Translates a SwiftUI `ScenePhase` into what it means for foreground-only
//  work — the `live-fs-topic` SSE subscription and widget state sync — so the
//  distinction between "still on screen" and "actually gone" lives in one
//  tested place rather than inline in the scene-phase handler.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// What a scene-phase change implies for work that should run only while the
/// app is on screen.
///
/// The three phases do not map onto a `Bool`, which is why this exists:
/// `.inactive` carries no information about whether the app is leaving. iOS
/// delivers it both as the first leg of a genuine exit
/// (`.active → .inactive → .background`) and for every transient interruption
/// that leaves the app visible — Control Center, Notification Center, the app
/// switcher, call banners, system alerts. Collapsing it to "backgrounded" tore
/// down the live-fs subscription on each of those, and since the app is still
/// foregrounded no further phase change was coming to restore it.
public enum ForegroundTransition: Equatable, Sendable {
    /// The app is on screen and interactive — start foreground-only work.
    case enterForeground
    /// The app has left the screen — tear foreground-only work down.
    case leaveForeground
    /// The phase changed but the app's on-screen state did not. Foreground-only
    /// work must survive untouched; a real exit announces itself with
    /// `.background` immediately after.
    case unchanged
}

public extension ForegroundTransition {
    /// Classifies the phase the app is entering.
    ///
    /// - Parameter phase: The new `ScenePhase`.
    init(enteringPhase phase: ScenePhase) {
        switch phase {
        case .active:
            self = .enterForeground
        case .background:
            self = .leaveForeground
        case .inactive:
            self = .unchanged
        @unknown default:
            // An unrecognised phase is not evidence the app left, and guessing
            // `.leaveForeground` would resurrect the bug this type prevents.
            self = .unchanged
        }
    }
}
