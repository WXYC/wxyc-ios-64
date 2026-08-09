//
//  ForegroundVisibility.swift
//  Core
//
//  Answers one question about a SwiftUI `ScenePhase`: does it tell you the app
//  is on screen, off screen, or nothing at all? Lives in Core because every
//  layer with a scene-phase consumer needs the same answer — the app target,
//  AppServices, and Wallpaper's Metal renderer among them.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// What a scene phase says about whether the app is on screen.
///
/// Three phases do not reduce to a `Bool`, which is the whole reason this
/// exists: `.inactive` carries no information about visibility. iOS delivers it
/// both as the first leg of a genuine exit
/// (`.active → .inactive → .background`) and for every transient interruption
/// that leaves the app visible — Control Center, Notification Center, the app
/// switcher, call banners, system alerts. Reading it as "off screen" tore down
/// the live-fs SSE subscription on each of those, and since the app was still
/// on screen no further phase change was coming to restore it.
///
/// This deliberately takes only the phase being entered, not the one being
/// left. The previous phase cannot disambiguate `.inactive` — an app can reach
/// it from `.active` on the way out *or* on the way back in — so a classifier
/// that consulted it would imply a precision it does not have.
///
/// Note that this answers *visibility*, which is not the same question as "may
/// I spend budgeted work?". Widget timeline reloads, for instance, only pay off
/// while the app is truly frontmost, so they key off `.active` directly rather
/// than off this type.
public enum ForegroundVisibility: Sendable {
    /// The app is on screen and interactive.
    case onScreen
    /// The app has left the screen.
    case offScreen
    /// The phase says nothing new about visibility. Whatever was true before
    /// still is; a real exit announces itself with `.background` right after.
    case noChange
}

public extension ForegroundVisibility {
    /// Classifies the phase the app is entering.
    ///
    /// - Parameter phase: The new `ScenePhase`.
    init(entering phase: ScenePhase) {
        switch phase {
        case .active:
            self = .onScreen
        case .background:
            self = .offScreen
        default:
            // `.inactive`, and any phase added in a future SDK. Neither is
            // evidence the app left, and guessing `.offScreen` is exactly the
            // bug this type exists to prevent.
            self = .noChange
        }
    }
}
