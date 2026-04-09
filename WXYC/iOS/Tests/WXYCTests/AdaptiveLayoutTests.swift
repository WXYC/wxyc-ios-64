//
//  AdaptiveLayoutTests.swift
//  WXYC
//
//  Tests for the selection logic used by RegularLayoutView to derive the selected
//  playcut from playlist entries and a selection ID binding.
//
//  Created by Jake Bromberg on 04/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC
@testable import Playlist

@Suite("RegularLayoutView Selection Logic")
struct AdaptiveLayoutTests {

    @Test("findPlaycut returns matching playcut for valid ID")
    func findPlaycutWithValidID() {
        let playcut = Playcut(
            id: 42,
            hour: 1000,
            chronOrderID: 42,
            timeCreated: 1000,
            songTitle: "VI Scose Poise",
            labelName: "Warp",
            artistName: "Autechre",
            releaseTitle: "Confield"
        )
        let entries: [any PlaylistEntry] = [
            Breakpoint(id: 1, hour: 900, chronOrderID: 1, timeCreated: 900),
            playcut,
            Playcut(id: 99, hour: 1100, chronOrderID: 99, timeCreated: 1100, songTitle: "Moon Pix", labelName: "Matador Records", artistName: "Cat Power", releaseTitle: "Moon Pix"),
        ]

        let result = RegularLayoutView.findPlaycut(id: 42, in: entries)

        #expect(result == playcut)
    }

    @Test("findPlaycut returns nil for nil ID")
    func findPlaycutWithNilID() {
        let entries: [any PlaylistEntry] = [
            Playcut(id: 1, hour: 1000, chronOrderID: 1, timeCreated: 1000, songTitle: "la paradoja", labelName: "Sonamos", artistName: "Juana Molina", releaseTitle: "DOGA"),
        ]

        let result = RegularLayoutView.findPlaycut(id: nil, in: entries)

        #expect(result == nil)
    }

    @Test("findPlaycut returns nil when ID matches no playcut")
    func findPlaycutWithNonexistentID() {
        let entries: [any PlaylistEntry] = [
            Playcut(id: 1, hour: 1000, chronOrderID: 1, timeCreated: 1000, songTitle: "Back, Baby", labelName: "Drag City", artistName: "Jessica Pratt", releaseTitle: "On Your Own Love Again"),
            Breakpoint(id: 2, hour: 1100, chronOrderID: 2, timeCreated: 1100),
        ]

        let result = RegularLayoutView.findPlaycut(id: 999, in: entries)

        #expect(result == nil)
    }

    @Test("findPlaycut ignores non-Playcut entries with same ID")
    func findPlaycutIgnoresNonPlaycutEntries() {
        let entries: [any PlaylistEntry] = [
            Breakpoint(id: 42, hour: 1000, chronOrderID: 42, timeCreated: 1000),
            Talkset(id: 42, hour: 1000, chronOrderID: 42, timeCreated: 1000),
        ]

        let result = RegularLayoutView.findPlaycut(id: 42, in: entries)

        #expect(result == nil)
    }

    @Test("findPlaycut returns nil for removed playcut, enabling stale selection clearing")
    func staleSelectionClearing() {
        let entries: [any PlaylistEntry] = [
            Playcut(id: 1, hour: 1000, chronOrderID: 1, timeCreated: 1000, songTitle: "Call Your Name", artistName: "Chuquimamani-Condori"),
            Playcut(id: 2, hour: 1100, chronOrderID: 2, timeCreated: 1100, songTitle: "Gasoline", labelName: "4AD", artistName: "Buck Meek", releaseTitle: "Gasoline"),
        ]

        // Selected playcut ID 99 was in a previous playlist but not this one
        let shouldClear = RegularLayoutView.findPlaycut(id: 99, in: entries) == nil

        #expect(shouldClear)
    }

    @Test("findPlaycut still finds playcut that remains after refresh")
    func selectionSurvivesRefresh() {
        let entries: [any PlaylistEntry] = [
            Playcut(id: 1, hour: 1000, chronOrderID: 1, timeCreated: 1000, songTitle: "Chateau Lobby #4", labelName: "Sub Pop", artistName: "Father John Misty", releaseTitle: "I Love You, Honeybear"),
            Playcut(id: 2, hour: 1100, chronOrderID: 2, timeCreated: 1100, songTitle: "Stay Chisel", labelName: "Matador Records", artistName: "Large Professor", releaseTitle: "1st Class"),
        ]

        let result = RegularLayoutView.findPlaycut(id: 1, in: entries)

        #expect(result != nil)
        #expect(result?.artistName == "Father John Misty")
    }
}
