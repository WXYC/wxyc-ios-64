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
private let entry = SpotlightEntry.stub(id: 13)
private let hogwash = SpecialtyShowRef(id: 3, slug: "hogwash", name: "Hogwash", shortName: "HW", tagline: "Weird and wonderful")

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
    PlaylistSectionCase(name: "a leading who's-on entry opens now playing, and the newest song is recent", items: [.spotlight(entry), .playcut(newest), .playcut(middle)], lead: .spotlight(entry), expected: [13: .nowPlaying, 12: .recentlyPlayed]),
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
        #expect(Playlist.widgetRecents(of: playcuts, lead: .spotlight(entry)).map(\.id) == [12, 11, 10])
        #expect(Playlist.widgetRecents(of: [], lead: .nothing).isEmpty)
    }

    @Test("widget content: song, song in a specialty program, program headline, who's-on line, recents under the station line, or the empty state", arguments: [
        (NowPlayingLead.song(newest), true, nil, WidgetContent.lead),
        (.song(newest), false, nil, .lead),
        (.song(newest), true, hogwash, .leadInProgram),
        (.song(newest), false, hogwash, .leadInProgram),
        (.specialtyCard(hogwash), true, hogwash, .program),
        (.specialtyCard(hogwash), false, hogwash, .program),
        // No program layouts (the large widget): a specialty show lays out as it did before, with no program
        // headline and no trimming.
        (.specialtyCard(hogwash), true, nil, .stationLine),
        (.specialtyCard(hogwash), false, nil, .empty),
        (.spotlight(entry), true, nil, .whosOn),
        (.spotlight(entry), false, hogwash, .whosOn),
        (.djHandle("Cat Power Hour"), true, nil, .stationLine),
        (.djHandle("Cat Power Hour"), false, nil, .empty),
        (.nothing, true, nil, .stationLine),
        (.nothing, false, nil, .empty),
    ])
    func widgetContent(lead: NowPlayingLead, hasRecents: Bool, program: SpecialtyShowRef?, expected: WidgetContent) {
        #expect(Playlist.widgetContent(lead: lead, hasRecents: hasRecents, program: program) == expected)
    }

    @Test("A specialty show's layouts show two recents; every other layout allows three", arguments: [
        (WidgetContent.leadInProgram, 2), (.program, 2), (.lead, 3), (.whosOn, 3), (.stationLine, 3), (.empty, 3),
    ])
    func recentLimit(content: WidgetContent, expected: Int) {
        #expect(content.recentLimit == expected)
    }
}
