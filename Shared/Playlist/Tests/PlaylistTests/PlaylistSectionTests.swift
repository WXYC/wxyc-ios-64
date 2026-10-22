//
//  PlaylistSectionTests.swift
//  Playlist
//
//  Verifies which playlist rows open the "now playing" and "recently played"
//  sections, and which songs the widget lists as recents, given what leads.
//
//  Created by Jake Bromberg on 10/21/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Playlist
import PlaylistTesting

private let newest = Playcut.stub(id: 12, showID: 42)
private let middle = Playcut.stub(id: 11, showID: 42)
private let oldest = Playcut.stub(id: 10, showID: 42)
private let previousShow = Playcut.stub(id: 9, showID: 41)

struct PlaylistSectionCase: Sendable, CustomTestStringConvertible {
    let name: String
    let items: [TimelineItem]
    let lead: NowPlayingLead
    let expected: [UInt64: PlaylistSection]
    var testDescription: String { name }
}

private let sectionCases: [PlaylistSectionCase] = [
    PlaylistSectionCase(name: "open show's song is now playing and the next is recent", items: [.playcut(newest), .playcut(middle)], lead: .song(newest), expected: [12: .nowPlaying, 11: .recentlyPlayed]),
    PlaylistSectionCase(name: "no song leads, so the first playcut opens recently played", items: [.playcut(previousShow), .playcut(oldest)], lead: .djHandle("Cat Power Hour"), expected: [9: .recentlyPlayed]),
    PlaylistSectionCase(name: "automation labels nothing now playing", items: [.playcut(newest), .playcut(middle)], lead: .nothing, expected: [12: .recentlyPlayed]),
    PlaylistSectionCase(name: "leader sorting second still gets the one now playing header", items: [.playcut(newest), .playcut(middle), .playcut(oldest)], lead: .song(middle), expected: [11: .nowPlaying, 12: .recentlyPlayed]),
    PlaylistSectionCase(name: "leader sorting third still gets the one now playing header", items: [.playcut(newest), .playcut(middle), .playcut(oldest)], lead: .song(oldest), expected: [10: .nowPlaying, 12: .recentlyPlayed]),
    PlaylistSectionCase(name: "a lone leader has no recently played row", items: [.playcut(newest)], lead: .song(newest), expected: [12: .nowPlaying]),
    PlaylistSectionCase(name: "no playcuts, no headers", items: [], lead: .nothing, expected: [:]),
]

@Suite("Playlist Section Tests")
struct PlaylistSectionTests {
    @Test("section header per row", arguments: sectionCases)
    func sections(_ testCase: PlaylistSectionCase) {
        #expect(Playlist.sections(of: testCase.items, lead: testCase.lead) == testCase.expected)
    }

    @Test("widget recents skip the leading song and keep all when none leads")
    func widgetRecents() {
        let playcuts = [oldest, newest, previousShow, middle]

        #expect(Playlist.widgetRecents(of: playcuts, lead: .song(newest)).map(\.id) == [11, 10, 9])
        #expect(Playlist.widgetRecents(of: playcuts, lead: .nothing).map(\.id) == [12, 11, 10])
        #expect(Playlist.widgetRecents(of: [], lead: .nothing).isEmpty)
    }
}
