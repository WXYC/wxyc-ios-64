//
//  RootTabPageTests.swift
//  WXYC
//
//  Verifies the root tab metadata. As of R1 (#490) there are three tabs — Now
//  Playing, On Tour, Info — each carrying the SF Symbols the app already speaks
//  on adjacent surfaces: radio in the widget and Siri intent, ticket in the Box
//  Office ticket language, info.circle in the playcut detail row.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC

@Suite("RootTabView Page")
struct RootTabPageTests {
    @Test("Three tabs in order: Now Playing, On Tour, Info")
    func caseOrder() {
        #expect(RootTabView.Page.allCases == [.playlist, .touring, .infoDetail])
    }

    @Test("The Now Playing tab is labeled for the live stream")
    func nowPlayingMetadata() {
        #expect(RootTabView.Page.playlist.title == "Now Playing")
        #expect(RootTabView.Page.playlist.systemImage == "radio")
    }

    @Test("The On Tour tab is labeled with the ticket glyph")
    func touringMetadata() {
        #expect(RootTabView.Page.touring.title == "On Tour")
        #expect(RootTabView.Page.touring.systemImage == "ticket")
    }

    @Test("The Info tab is labeled as the station page")
    func infoMetadata() {
        #expect(RootTabView.Page.infoDetail.title == "Info")
        #expect(RootTabView.Page.infoDetail.systemImage == "info.circle")
    }

    @Test("Each tab carries a stable accessibility identifier")
    func accessibilityIdentifiers() {
        #expect(RootTabView.Page.playlist.accessibilityIdentifier == "tab.nowPlaying")
        #expect(RootTabView.Page.touring.accessibilityIdentifier == "tab.touring")
        #expect(RootTabView.Page.infoDetail.accessibilityIdentifier == "tab.info")
    }
}
