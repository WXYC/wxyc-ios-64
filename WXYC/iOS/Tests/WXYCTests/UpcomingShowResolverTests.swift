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
import SwiftUI
@testable import WXYC

/// Resolves nothing, ever — distinguishable from both real resolvers precisely
/// because they *would* return a show for a playcut that carries one.
private struct NeverResolvingUpcomingShowResolver: UpcomingShowResolving {
    func upcomingShow(for playcut: Playcut) -> Concert? { nil }
}

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

    // MARK: - Environment default

    /// The behavioural pin on `\.upcomingShowResolver`'s uninjected default.
    /// Both configurations' resolvers return the embedded show verbatim when the
    /// playcut carries one — release because that is all it does, DEBUG because
    /// it prefers a real embed over its mock — so this holds without a `#if`
    /// and would fail for a default that resolved to neither.
    ///
    /// Deliberately behavioural rather than identity-based: `UpcomingShowResolving`
    /// carries no `AnyObject` bound and both resolvers are stateless structs, so
    /// `===` does not compile against the existential and two instances are
    /// indistinguishable anyway.
    @Test("An uninjected read still returns the embedded show")
    func uninjectedReadReturnsEmbeddedShow() {
        let show = makeShow()
        let playcut = makePlaycut(upcomingShow: show)

        #expect(EnvironmentValues().upcomingShowResolver.upcomingShow(for: playcut) == show)
    }

    /// The uninjected default is the resolver this configuration ships, not
    /// merely something embed-shaped. Pins which arm of the `#if` the default
    /// selects — the test above passes for either.
    @Test("An uninjected read resolves to this configuration's resolver")
    func uninjectedReadResolvesToConfiguredResolver() {
        let resolved = EnvironmentValues().upcomingShowResolver

        #if DEBUG
        #expect(resolved is DebugUpcomingShowResolver)
        #else
        #expect(resolved is EmbeddedUpcomingShowResolver)
        #endif
    }

    /// Guards the getter/setter pair against addressing different keys, which
    /// would leave every reader on the default. The injected resolver returns
    /// `nil` for a playcut that both real ones would resolve, so a read falling
    /// through to the default fails here rather than coincidentally matching.
    @Test("An injected resolver is the one that resolves")
    func injectedResolverIsWhatResolves() {
        let playcut = makePlaycut(upcomingShow: makeShow())
        var values = EnvironmentValues()
        values.upcomingShowResolver = NeverResolvingUpcomingShowResolver()

        #expect(values.upcomingShowResolver.upcomingShow(for: playcut) == nil)
    }
}
