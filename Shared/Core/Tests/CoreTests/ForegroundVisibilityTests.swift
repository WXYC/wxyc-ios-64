//
//  ForegroundVisibilityTests.swift
//  Core
//
//  Pins what each `ScenePhase` says about visibility — most of all that
//  `.inactive` says nothing, rather than saying "off screen". Reading it as off
//  screen tore down the `live-fs-topic` SSE subscription every time the user
//  opened Control Center or a notification banner slid in, leaving the playlist
//  on its 300 s reconciliation poll. See WXYC/wxyc-ios-64#269 for the
//  subscription this protects.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import SwiftUI
@testable import Core

@Suite("Foreground visibility")
struct ForegroundVisibilityTests {

    @Test(
        "Each scene phase reports what it actually knows about visibility",
        arguments: [
            (ScenePhase.active, ForegroundVisibility.onScreen),
            (ScenePhase.background, ForegroundVisibility.offScreen),
            // The regression this suite exists to prevent. iOS delivers
            // `.inactive` for Control Center, Notification Center, the app
            // switcher, call banners and system alerts — all with the app
            // still on screen — and again as the first leg of a genuine
            // `.active -> .inactive -> .background` exit. Only the
            // `.background` that follows is proof the app actually left, so
            // `.inactive` alone must report no change.
            (ScenePhase.inactive, ForegroundVisibility.noChange),
        ]
    )
    func phaseReportsVisibility(phase: ScenePhase, expected: ForegroundVisibility) {
        #expect(ForegroundVisibility(entering: phase) == expected)
    }
}
