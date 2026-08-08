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
        .previewFixture(
            id: 900_000 + Int(playcut.id % 100_000),
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

private struct UpcomingShowResolverKey: EnvironmentKey {
    // Reads the embedded feed value in release; a DEBUG toggle can synthesize a
    // mock for the now-playing row so the feature is exercisable pre-data.
    static let defaultValue: any UpcomingShowResolving = {
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
    var upcomingShowResolver: any UpcomingShowResolving {
        get { self[UpcomingShowResolverKey.self] }
        set { self[UpcomingShowResolverKey.self] = newValue }
    }
}
