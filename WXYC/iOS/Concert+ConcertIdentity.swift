//
//  Concert+ConcertIdentity.swift
//  WXYC
//
//  The one bridge between `Concert` (Concerts) and `ConcertIdentity`
//  (Analytics). `Concerts` may not depend on `Analytics` — that edge would put
//  PostHog in every Concerts consumer's build graph — so the mapping lives with
//  a consumer of both, as `SongLikeToggled+LikeAnalyticsFields` does.
//
//  It sits in the app target rather than `Shared/Intents` (which also depends on
//  both) because the app target is where all but one caller lives. The exception
//  is `AddConcertToCalendarIntent`, which is itself app-target for the
//  `@Dependency`-outside-perform reason `AddConcertToCalendarQuery`'s header
//  documents.
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
    /// anything failing: the query that misses half its data still runs.
    ///
    /// `artist` is ``headliningArtistRaw`` — **not** ``headlineName``. That
    /// distinction is the whole correctness of this type. `headlineName` is
    /// `title ?? headliningArtistRaw`, a *display* string that becomes the
    /// festival or billed-night name when a show has one, while
    /// ``headliningArtistId`` is always resolved from `headliningArtistRaw`. Pair
    /// them and a festival ships `artist: "Hopscotch Music Festival"` next to the
    /// headliner's catalog id: one id carrying two different names across events,
    /// so `GROUP BY artist` splits a band between its real name and a festival
    /// string, and joining to `song_like_toggled.artist` drops every titled show.
    /// `headliningArtistRaw` is also, per its own documentation, the field
    /// matched against a playcut's artist — the same keyspace the likes events
    /// use. The billed title isn't lost; it is recoverable by joining
    /// `concert_id`, which every one of these events carries.
    ///
    /// `artistId` stays `nil` for a headliner the WXYC catalog doesn't know
    /// rather than falling back to a name lookup: a wrong id is a wrong join, an
    /// absent one is merely absent.
    ///
    /// `nonisolated` because it is pure value math over an immutable `Concert`
    /// and touches nothing shared. Without it the app target's default MainActor
    /// isolation applies, and `AddConcertToCalendarIntent.perform()` — which runs
    /// nonisolated — can't name the band on its way past.
    nonisolated var analyticsIdentity: ConcertIdentity {
        ConcertIdentity(
            artist: headliningArtistRaw,
            artistId: headliningArtistId,
            venue: venue.name,
            concertId: id,
            status: status.rawValue
        )
    }
}
