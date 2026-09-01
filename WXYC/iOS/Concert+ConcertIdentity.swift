//
//  Concert+ConcertIdentity.swift
//  WXYC
//
//  The one bridge between `Concert` (Concerts) and `ConcertIdentity`
//  (Analytics). Neither package may depend on the other — an Analytics edge
//  would put PostHog in every Concerts consumer's build graph — so the app
//  target, which imports both, is the only place the two types can meet. Same
//  arrangement, and the same reason, as `SongLikeToggled+LikeAnalyticsFields`.
//
//  Top-level rather than under `Views/OnTour/` because the ticket surfaces that
//  use it are split across two folders: the concert detail and the row live
//  under On Tour, the Box Office keepsake under the playcut detail.
//
//  Created by Jake Bromberg on 08/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import Concerts

extension Concert {
    /// The show as the On Tour intent events name it.
    ///
    /// Read from here at every capture site rather than spelled out inline,
    /// because the mapping is exactly where the sites can diverge without
    /// anything failing: `headliningArtistRaw` in place of ``headlineName`` at
    /// one call site splits one band into two rows in PostHog, and the query
    /// that misses half its data still runs.
    ///
    /// `artist` is ``headlineName``, the billed name the listener actually read
    /// — the festival or package title when the show has one. `artistId` stays
    /// `nil` for a headliner the WXYC catalog doesn't know rather than falling
    /// back to a name lookup: a wrong id is a wrong join, and an absent one is
    /// merely an absent one.
    ///
    /// `nonisolated` because it is pure value math over an immutable `Concert`
    /// and touches nothing shared. Without it the app target's default MainActor
    /// isolation applies, and `AddConcertToCalendarIntent.perform()` — which runs
    /// nonisolated — can't name the band on its way past.
    nonisolated var analyticsIdentity: ConcertIdentity {
        ConcertIdentity(
            artist: headlineName,
            artistId: headliningArtistId,
            venue: venue.name,
            concertId: id,
            status: status.rawValue
        )
    }
}
