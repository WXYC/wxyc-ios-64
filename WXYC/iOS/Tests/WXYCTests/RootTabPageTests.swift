//
//  RootTabPageTests.swift
//  WXYC
//
//  Verifies the root tab metadata. As of the liked-songs feature (#492) there
//  are four tabs — Now Playing, On Tour, Liked, Station — each carrying the SF
//  Symbols the app already speaks on adjacent surfaces: radio in the widget and
//  Siri intent, ticket in the Box Office ticket language, heart in the playcut
//  like affordance, and the antenna for the station page (the Info junk drawer
//  regrouped; see docs/ideas/info-tab-junk-drawer.html).
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import WXYC

@Suite("RootTabView Page")
struct RootTabPageTests {
    @Test("Four tabs in order: Now Playing, On Tour, Liked, Station")
    func caseOrder() {
        #expect(RootTabView.Page.allCases == [.playlist, .onTour, .liked, .station])
    }

    @Test("The Now Playing tab is labeled for the live stream")
    func nowPlayingMetadata() {
        #expect(RootTabView.Page.playlist.title == "Now Playing")
        #expect(RootTabView.Page.playlist.systemImage == "radio")
    }

    @Test("The On Tour tab is labeled with the ticket glyph")
    func onTourMetadata() {
        #expect(RootTabView.Page.onTour.title == "On Tour")
        #expect(RootTabView.Page.onTour.systemImage == "ticket")
    }

    @Test("The Liked tab is labeled with the heart glyph")
    func likedMetadata() {
        #expect(RootTabView.Page.liked.title == "Liked")
        #expect(RootTabView.Page.liked.systemImage == "heart")
    }

    @Test("The Station tab is labeled with the antenna glyph")
    func stationMetadata() {
        #expect(RootTabView.Page.station.title == "Station")
        #expect(RootTabView.Page.station.systemImage == "antenna.radiowaves.left.and.right")
    }

    @Test("Each tab carries a stable accessibility identifier")
    func accessibilityIdentifiers() {
        #expect(RootTabView.Page.playlist.accessibilityIdentifier == "tab.nowPlaying")
        #expect(RootTabView.Page.onTour.accessibilityIdentifier == "tab.onTour")
        #expect(RootTabView.Page.liked.accessibilityIdentifier == "tab.liked")
        #expect(RootTabView.Page.station.accessibilityIdentifier == "tab.station")
    }
}
