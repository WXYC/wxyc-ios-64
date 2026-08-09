//
//  ForegroundTransitionTests.swift
//  AppServices
//
//  Pins what each `ScenePhase` means for foreground-only work — most of all
//  that `.inactive` means "still on screen behind a transient interruption",
//  not "backgrounded". Treating it as backgrounding tore down the
//  `live-fs-topic` SSE subscription every time the user opened Control Center
//  or a notification banner slid in, leaving the playlist on its 300 s
//  reconciliation poll. See WXYC/wxyc-ios-64#269 for the subscription this
//  protects.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import SwiftUI
@testable import AppServices

@Suite("Foreground transition")
struct ForegroundTransitionTests {

    @Test(
        "Each scene phase maps to the transition its on-screen state implies",
        arguments: [
            (ScenePhase.active, ForegroundTransition.enterForeground),
            (ScenePhase.background, ForegroundTransition.leaveForeground),
            // The regression this suite exists to prevent. iOS delivers
            // `.inactive` for Control Center, Notification Center, the app
            // switcher, call banners and system alerts — all with the app
            // still on screen — and again as the first leg of a genuine
            // `.active -> .inactive -> .background` exit. Only the
            // `.background` that follows is proof the app actually left, so
            // `.inactive` alone must change nothing.
            (ScenePhase.inactive, ForegroundTransition.unchanged),
        ]
    )
    func phaseMapsToTransition(phase: ScenePhase, expected: ForegroundTransition) {
        #expect(ForegroundTransition(enteringPhase: phase) == expected)
    }

    @Test("A transient interruption never reports leaving the foreground")
    func transientInterruptionKeepsForegroundWork() {
        // Control Center down and back up: the exact sequence that was
        // tearing the SSE subscription down mid-session.
        let phases: [ScenePhase] = [.active, .inactive, .active]
        let transitions = phases.map { ForegroundTransition(enteringPhase: $0) }

        #expect(!transitions.contains(.leaveForeground))
    }

    @Test("A genuine exit still reports leaving the foreground")
    func backgroundingStillTearsDown() {
        // Non-vacuity guard for the test above: `.inactive` becoming inert
        // must not also make real backgrounding inert, or the subscription
        // would survive into the background and burn a connection there.
        let phases: [ScenePhase] = [.active, .inactive, .background]
        let transitions = phases.map { ForegroundTransition(enteringPhase: $0) }

        #expect(transitions.last == .leaveForeground)
        #expect(transitions.filter { $0 == .leaveForeground }.count == 1)
    }
}
