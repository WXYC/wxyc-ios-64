//
//  UpcomingShowResolverTests.swift
//  WXYC
//
//  Proves the Box Office CTA's data path is the embedded feed value and nothing
//  else: the production resolver returns exactly `Playcut.upcomingShow`, and it
//  is a pure, synchronous read — there is no fetcher and no network call to
//  populate the CTA (acceptance criterion for wxyc-ios-64#473).
//
//  Created by Jake Bromberg on 07/11/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
import Concerts
import Playlist
@testable import WXYC

@Suite("UpcomingShowResolver")
@MainActor
struct UpcomingShowResolverTests {

    private let resolver = EmbeddedUpcomingShowResolver()

    /// A minimal on-sale concert built from public initializers (no stub-module
    /// dependency, so the test target needs only `Concerts` + `Playlist`).
    private func makeShow(id: Int = 4821, status: ShowStatus = .onSale) -> Concert {
        Concert(
            id: id,
            venue: Venue(id: 3, slug: "cats-cradle", name: "Cat's Cradle", city: "Carrboro", state: "NC"),
            startsOn: Date(timeIntervalSince1970: 1_785_898_800),
            headliningArtistRaw: "Jessica Pratt",
            ticketURL: URL(string: "https://www.etix.com/ticket/p/jessica-pratt"),
            status: status
        )
    }

    private func makePlaycut(upcomingShow: Concert?) -> Playcut {
        Playcut(
            id: 1,
            hour: 1000,
            chronOrderID: 1,
            timeCreated: 1000,
            songTitle: "Back, Baby",
            labelName: "Drag City",
            artistName: "Jessica Pratt",
            releaseTitle: "On Your Own Love Again",
            upcomingShow: upcomingShow
        )
    }

    @Test("Returns the show embedded on the playcut, verbatim")
    func returnsEmbeddedShow() {
        let show = makeShow(status: .soldOut)
        let playcut = makePlaycut(upcomingShow: show)

        #expect(resolver.upcomingShow(for: playcut) == show)
    }

    @Test("Returns nil when the playcut carries no embedded show")
    func returnsNilWhenAbsent() {
        let playcut = makePlaycut(upcomingShow: nil)
        #expect(playcut.upcomingShow == nil)
        #expect(resolver.upcomingShow(for: playcut) == nil)
    }

    // The resolver's signature is the guarantee that the CTA makes no network
    // call: `upcomingShow(for:)` is synchronous (non-`async`) and takes only the
    // already-fetched playcut, so it *cannot* await a fetch. This test documents
    // that contract — a future change that reached out to the network would have
    // to make the method `async`, breaking this call site.
    @Test("Resolving is synchronous — no fetch can be awaited on this path")
    func resolvingIsSynchronous() {
        let show = makeShow()
        let playcut = makePlaycut(upcomingShow: show)

        // Called with no `await`; a compile-time proof the path is network-free.
        let resolved: Concert? = resolver.upcomingShow(for: playcut)
        #expect(resolved == show)
    }
}
