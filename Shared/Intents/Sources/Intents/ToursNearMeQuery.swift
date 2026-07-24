//
//  ToursNearMeQuery.swift
//  Intents
//
//  The testable core behind the "What WXYC artists are touring near me?" Siri
//  intent (OT-C2, WXYC/wxyc-ios-64#625): fetches the curated concert window
//  once with fixed, likes-independent parameters, narrows it to a date
//  window, then prefers the listener's on-device liked-artist intersection --
//  reusing `ForYouShelf`'s loved tier exactly as the On Tour For You shelf
//  does -- falling back to the plain date-filtered window when nothing
//  matches, so a listener with no likes still gets an answer.
//
//  Privacy: `fetchRequestParameters` never takes a `likedArtists` argument --
//  the signature itself is the enforced guarantee that no taste signal can
//  flow into the network request. The intersection happens entirely in
//  `matchingConcerts`, a synchronous, no-I/O function over the already-fetched
//  public `curated=true` window (WXYC/wxyc-ios-64#493's invariant, restated
//  for Siri). See `ForYouShelfTests`/`ToursNearMeQueryTests` for the
//  assertions this claim rests on.
//
//  The `AppIntent` itself (`ToursNearMe`) lives in the app target, alongside
//  `WhatsPlayingOnWXYC`/`MakeARequest`, because it needs app-level service
//  wiring (`ConcertsFetcher(tokenProvider:)`, the likes-store file path) this
//  package deliberately doesn't depend on. `resolve(fetcher:...)` is the thin
//  seam that keeps that wiring's *behavior* unit-testable here regardless.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Foundation

public enum ToursNearMeQuery {

    /// The `GET /concerts` page size requested for the Siri answer. One page
    /// covers the whole curated window in practice (mirrors the server's own
    /// cap, documented on `ConcertsFetcher.fetchConcerts(limit:)`), and a Siri
    /// response has a tight latency budget, so this deliberately fetches a
    /// single page rather than exhausting pagination the way `OnTourModel`
    /// does for the full On Tour tab.
    public static let fetchLimit = 100

    /// The maximum concerts returned to Siri/Spotlight. A spoken dialog and an
    /// interactive snippet both degrade badly if a busy Triangle week floods
    /// them with entries, so the answer is capped to the soonest matches
    /// (``matchingConcerts(concerts:dateWindow:likedArtists:now:)`` preserves
    /// date-ascending order).
    public static let resultCap = 5

    /// The fixed parameters for the curated-window fetch. **Carries no
    /// liked-artist data by construction** -- there is no parameter through
    /// which it could. This is the privacy guarantee for the network half of
    /// the intent: the request is identical no matter who's asking or what
    /// they've liked.
    public static func fetchRequestParameters(
        now: Date
    ) -> (curated: Bool, from: Date, to: Date?, page: Int, limit: Int) {
        (curated: true, from: now, to: nil, page: 1, limit: fetchLimit)
    }

    /// Narrows `concerts` to `dateWindow`, then prefers the listener's loved
    /// concerts (headliner is a liked artist, via ``ForYouShelf``'s loved
    /// tier) when any exist, else returns the plain date-filtered set. Pure,
    /// synchronous, no I/O -- the on-device intersection the privacy
    /// invariant requires.
    ///
    /// - Parameters:
    ///   - concerts: the already-fetched curated window, any order.
    ///   - dateWindow: the Siri-selected date window.
    ///   - likedArtists: the listener's id-bearing liked artists, read
    ///     on-device. May be empty (cold start) -- the date-filtered set
    ///     alone still answers the query.
    ///   - now: injected clock so the relative date window is deterministic
    ///     under test.
    public static func matchingConcerts(
        concerts: [Concert],
        dateWindow: ConcertFilterState.DateWindow,
        likedArtists: [LikedArtist],
        now: Date
    ) -> [Concert] {
        let filter = ConcertFilterState(dateWindow: dateWindow)
        let dateFiltered = concerts.filter { filter.matches($0, now: now) }
        let loved = ForYouShelf.recommendations(concerts: dateFiltered, likedArtists: likedArtists).map(\.concert)
        return loved.isEmpty ? dateFiltered : loved
    }

    /// Fetches the curated window and resolves it to the capped, matched
    /// concerts the intent presents. Returns the domain ``Concert`` values
    /// (not ``ConcertEntity``) because the interactive snippet renders a
    /// poster and a "Get Tickets" link from ``Concert/imageURL`` /
    /// ``Concert/ctaURL`` -- fields ``ConcertEntity`` deliberately doesn't
    /// carry (it's the minimal Spotlight-identity shape from OT-F1; the richer
    /// attributes are OT-C3/OT-C4). The intent maps this list to
    /// `[ConcertEntity]` itself for the `ReturnsValue` result.
    ///
    /// The one place production and tests share: a test drives this with a
    /// stub ``ConcertsFetching`` and can assert both the match behavior and --
    /// via the stub's recorded requests -- that varying `likedArtists` never
    /// varies the request.
    public static func resolve(
        fetcher: any ConcertsFetching,
        dateWindow: ConcertFilterState.DateWindow,
        likedArtists: [LikedArtist],
        now: Date
    ) async throws -> [Concert] {
        let params = fetchRequestParameters(now: now)
        let response = try await fetcher.fetchConcerts(
            curated: params.curated,
            from: params.from,
            to: params.to,
            page: params.page,
            limit: params.limit
        )
        let matches = matchingConcerts(
            concerts: response.concerts,
            dateWindow: dateWindow,
            likedArtists: likedArtists,
            now: now
        )
        return Array(matches.prefix(resultCap))
    }
}
