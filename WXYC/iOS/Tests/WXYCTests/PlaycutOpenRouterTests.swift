//
//  PlaycutOpenRouterTests.swift
//  WXYC
//
//  Verifies the pure "which row should PlaylistView scroll to" resolution
//  the #434 deep-link wiring hands off from a `PendingPlaycutLink` to the
//  loaded playlist timeline.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import Testing
@testable import WXYC

@Suite("PlaycutOpenRouter")
struct PlaycutOpenRouterTests {
    @Test("Resolves the target id when the playcut is in the loaded timeline")
    func resolvesPresentPlaycut() {
        let entries: [any PlaylistEntry] = [
            makePlaycut(id: 1, artistName: "Juana Molina"),
            makePlaycut(id: 2, artistName: "Stereolab"),
        ]

        let target = PlaycutOpenRouter.scrollTarget(for: PendingPlaycutLink(id: 2), in: entries)

        #expect(target == 2)
    }

    @Test("Resolves nil when the playcut isn't in the loaded timeline")
    func resolvesNilForMissingPlaycut() {
        let entries: [any PlaylistEntry] = [makePlaycut(id: 1, artistName: "Juana Molina")]

        let target = PlaycutOpenRouter.scrollTarget(for: PendingPlaycutLink(id: 404), in: entries)

        #expect(target == nil)
    }

    @Test("Resolves nil against an empty timeline (not yet loaded)")
    func resolvesNilForEmptyTimeline() {
        let target = PlaycutOpenRouter.scrollTarget(for: PendingPlaycutLink(id: 1), in: [])

        #expect(target == nil)
    }

    @Test("Doesn't match a non-Playcut entry that happens to share the target id")
    func doesNotMatchNonPlaycutEntry() {
        let entries: [any PlaylistEntry] = [Breakpoint(id: 7, hour: 1000, chronOrderID: 1, timeCreated: 1000)]

        let target = PlaycutOpenRouter.scrollTarget(for: PendingPlaycutLink(id: 7), in: entries)

        #expect(target == nil)
    }

    /// A minimal playcut built from the public initializer (no stub-module
    /// dependency), mirroring `UpcomingShowResolverTests.makePlaycut`.
    private func makePlaycut(id: UInt64, artistName: String) -> Playcut {
        Playcut(
            id: id,
            hour: 1000,
            chronOrderID: id,
            timeCreated: 1000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: artistName,
            releaseTitle: "DOGA"
        )
    }
}
