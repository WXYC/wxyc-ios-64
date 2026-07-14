//
//  RootTabPageTests.swift
//  WXYC
//
//  Verifies the root tab metadata for the R0 tab-bar migration: two tabs
//  (Now Playing, Info) carrying the SF Symbols the app already speaks on
//  adjacent surfaces — radio in the widget and Siri intent, info.circle in
//  the playcut detail row.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC

@Suite("RootTabView Page")
struct RootTabPageTests {
    @Test("R0 has exactly two tabs, Now Playing first")
    func caseOrder() {
        #expect(RootTabView.Page.allCases == [.playlist, .infoDetail])
    }

    @Test("The Now Playing tab is labeled for the live stream")
    func nowPlayingMetadata() {
        #expect(RootTabView.Page.playlist.title == "Now Playing")
        #expect(RootTabView.Page.playlist.systemImage == "radio")
    }

    @Test("The Info tab is labeled as the station page")
    func infoMetadata() {
        #expect(RootTabView.Page.infoDetail.title == "Info")
        #expect(RootTabView.Page.infoDetail.systemImage == "info.circle")
    }

    @Test("Each tab carries a stable accessibility identifier")
    func accessibilityIdentifiers() {
        #expect(RootTabView.Page.playlist.accessibilityIdentifier == "tab.nowPlaying")
        #expect(RootTabView.Page.infoDetail.accessibilityIdentifier == "tab.info")
    }
}
