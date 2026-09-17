//
//  UpcomingShowProvider.swift
//  WXYC
//
//  Resolves the upcoming Triangle-area show to render on a playcut. The show
//  arrives EMBEDDED on the flowsheet feed (`Playcut.upcomingShow`), joined
//  server-side by Backend-Service when the played track's artist matches a
//  curated upcoming concert — so resolving it is a pure, synchronous read of the
//  already-fetched playcut. There is no fetcher here and no network call on this
//  path: if the feed carried no show, the CTA renders nothing.
//
//  In DEBUG a toggle-driven mock can override the embedded value on the
//  now-playing row so the Box Office ticket is exercisable in the running app
//  without waiting for a real matching show.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Playlist
import SwiftUI
#if DEBUG
import DebugPanel
#endif

/// Resolves the upcoming show for a played track. Synchronous and network-free:
/// the show is read straight off the playcut, where the backend embedded it on
/// the feed. Injected through the environment so the views stay decoupled from
/// the (debug-only) override policy.
protocol UpcomingShowResolving: Sendable {
    /// The upcoming show to render for `playcut`, or `nil` for none. Pure — makes
    /// no network request.
    @MainActor func upcomingShow(for playcut: Playcut) -> Concert?
}

/// The production resolver: returns exactly what the feed embedded on the
/// playcut. No fallback fetch — an absent embed renders no CTA.
struct EmbeddedUpcomingShowResolver: UpcomingShowResolving {
    func upcomingShow(for playcut: Playcut) -> Concert? {
        playcut.upcomingShow
    }
}

#if DEBUG
/// Development resolver: prefers a real embedded show, and otherwise synthesizes
/// a mock for the now-playing (first) playcut while the "Mock ticket on first
/// item" debug toggle is on. Lets the Box Office ticket be exercised end-to-end
/// in the running app before real curated matches flow through the feed. Still
/// network-free — the mock is fabricated locally.
struct DebugUpcomingShowResolver: UpcomingShowResolving {
    func upcomingShow(for playcut: Playcut) -> Concert? {
        if let embedded = playcut.upcomingShow { return embedded }
        let debug = OnTourShowsDebugState.shared
        guard debug.mockFirstItemEnabled, debug.firstPlaycutID == playcut.id else {
            return nil
        }
        return Self.mockShow(for: playcut)
    }

    /// A plausible on-sale show at Cat's Cradle, titled after the played artist so
    /// the mock reads coherently ("Playing Near You" for whoever is on now).
    ///
    /// Shared with the dev-only tour-notification wiring (`Singletonia`) so a test
    /// notification points at the same fabricated show the Box Office ticket shows.
    static func mockShow(for playcut: Playcut) -> Concert {
        // `catsCradleWithoutAddress`: this mock built its venue with
        // `address: nil`, and both the Box Office ticket's venue line and the
        // detail view's address line render the street address when it's there.
        .previewFixture(
            id: 900_000 + Int(playcut.id % 100_000),
            venue: .catsCradleWithoutAddress,
            headliningArtistRaw: playcut.artistName,
            supportingArtistsRaw: ["Tapir!"],
            ticketURL: URL(string: "https://www.etix.com/ticket/p/mock"),
            eventURL: URL(string: "https://catscradle.com/event/mock"),
            status: .onSale
        )
    }
}
#endif

// MARK: - Environment

/// What `\.upcomingShowResolver` resolves to when nothing was injected: the
/// embedded feed value in release, and in DEBUG a toggle-driven mock for the
/// now-playing row so the feature is exercisable pre-data.
///
/// Hoisted to a `static let` rather than written inline in the `@Entry` default
/// below, because `@Entry` emits a *computed* `defaultValue` — the expression it
/// is handed runs on every lookup that misses, where this constant runs once per
/// process. Both resolvers are stateless structs behind an existential with no
/// `AnyObject` bound, so rebuilding one costs nothing and no caller can tell two
/// apart; naming it is this codebase's rule that a default is a reference, not a
/// construction, rather than a fix for a hazard. It also keeps the `#if` out of
/// the macro's input.
private enum UpcomingShowResolverDefault {
    static let shared: any UpcomingShowResolving = {
        #if DEBUG
        DebugUpcomingShowResolver()
        #else
        EmbeddedUpcomingShowResolver()
        #endif
    }()
}

extension EnvironmentValues {
    /// The resolver that turns a playcut into its upcoming show. Defaults to the
    /// embedded-feed read (release) / a toggle-driven mock (DEBUG). Both are
    /// synchronous and make no network call.
    @Entry var upcomingShowResolver: any UpcomingShowResolving = UpcomingShowResolverDefault.shared
}
