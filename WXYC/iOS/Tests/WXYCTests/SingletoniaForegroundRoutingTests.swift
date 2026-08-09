//
//  SingletoniaForegroundRoutingTests.swift
//  WXYC
//
//  Pins the one thing about scene-phase routing that is easy to get wrong: the
//  two consumers disagree about `.inactive`, and collapsing them back into a
//  single `Bool` is a regression in whichever direction it collapses.
//
//  Reading `.inactive` as "off screen" tears down the `live-fs-topic` SSE
//  subscription while the app is still visible behind Control Center, and
//  nothing restores it. Reading it as "on screen" holds the widget-reload guard
//  open, and an unfocused iPad Split View pane or non-frontmost Catalyst window
//  can sit `.inactive` for hours, spending a budgeted timeline reload on every
//  live-fs event that arrives. `setScenePhase(_:)` itself isn't reachable
//  without standing up the whole object graph, so the decision is factored into
//  a pure helper and tested directly — the same approach
//  `SingletoniaLikedStorageTests` takes.
//
//  Created by Jake Bromberg on 08/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import SwiftUI
import Testing
@testable import WXYC

@MainActor
@Suite("Singletonia foreground routing")
struct SingletoniaForegroundRoutingTests {

    @Test(
        "Each phase routes to both consumers under their own rule",
        arguments: [
            (ScenePhase.active, true, ForegroundVisibility.onScreen),
            (ScenePhase.background, false, ForegroundVisibility.offScreen),
            // The case the two consumers disagree on, and the only row that
            // can regress quietly: widgets stop, the subscription stays.
            (ScenePhase.inactive, false, ForegroundVisibility.noChange),
        ]
    )
    func phaseRoutesToBothConsumers(
        phase: ScenePhase,
        expectedWidgets: Bool,
        expectedPlaylist: ForegroundVisibility
    ) {
        let routing = Singletonia.foregroundRouting(for: phase)

        #expect(routing.widgetsForegrounded == expectedWidgets)
        #expect(routing.playlistVisibility == expectedPlaylist)
    }

    @Test("A transient interruption stops widget reloads without dropping the subscription")
    func inactiveSplitsTheTwoConsumers() {
        let routing = Singletonia.foregroundRouting(for: .inactive)

        // Stated as an inequality because the failure this guards against is
        // precisely the two collapsing back into one value.
        #expect(routing.widgetsForegrounded == false)
        #expect(routing.playlistVisibility != .offScreen)
    }
}
