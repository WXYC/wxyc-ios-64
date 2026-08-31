//
//  OnTourEvents.swift
//  Analytics
//
//  Structured analytics for the On Tour tab, in two tiers.
//
//  BROWSE events — tab/sheet lifecycle, facet names, shelf and card counts —
//  carry no artist identity. Which bands a listener is shown, and which of them
//  came from their own likes, stays on the device: the For You tiers are
//  computed locally against the likes store, so naming them here would ship the
//  taste inference the shelf exists to keep private.
//
//  INTENT events — currently only ``ConcertTicketsTapped`` — do carry the band,
//  the venue, and the concert. A listener tapping through to a box office has
//  declared an interest in a specific show, and WXYC wants to know which bands
//  drive that, the same way ``SongLikeToggled`` records which bands get liked
//  (the 2026-08-21 likes-identity reversal). Identity-bearing events reuse
//  `SongLikeToggled`'s `artist` / `artist_id` key names exactly so the two can
//  be joined without aliasing.
//
//  The line is deliberate: *what we showed you* is anonymous, *what you chose*
//  is not. Adding identity to a browse event is a product decision, not a
//  cleanup — the counts-only assertions in the tests are what hold that line.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - On Tour tab

/// Event fired once per launch, the first time the On Tour tab is opened. The
/// view latches on first appearance, so switching away and back does not re-fire.
@AnalyticsEvent
public struct OnTourTabViewed {
    public init() {}
}

/// Event fired when the filter sheet is opened.
@AnalyticsEvent
public struct OnTourFilterSheetOpened {
    public init() {}
}

/// Event fired on an explicit user filter action — changing a facet, clearing a
/// facet pill, or resetting. `facet` is the changed facet's key ("date", "venue",
/// "free", "all_ages", "genre") or "reset" for a full clear; `activeCount` is the
/// resulting number of engaged facet groups. Never carries any concert or artist data.
@AnalyticsEvent
public struct OnTourFilterApplied {
    public let facet: String
    public let activeCount: Int

    public init(facet: String, activeCount: Int) {
        self.facet = facet
        self.activeCount = activeCount
    }
}

/// Event fired when an active filter narrows the window to zero shows.
@AnalyticsEvent
public struct OnTourFilteredToZero {
    public init() {}
}

// MARK: - For You shelf (#493)

/// Event fired once per launch, the first time the "Heard on WXYC" recommendation
/// shelf renders with at least one card. `lovedCount` / `stationCount` are the
/// per-tier sizes at that first render — volume without identity, per the On Tour
/// privacy invariant. `stationCount` is the cold-start station-recommended tier
/// (#577). Never carries a concert or artist id: which artists the listener likes
/// stays on the device.
@AnalyticsEvent
public struct ForYouShelfImpression {
    public let lovedCount: Int
    public let stationCount: Int

    public init(lovedCount: Int, stationCount: Int) {
        self.lovedCount = lovedCount
        self.stationCount = stationCount
    }
}

/// Event fired when a For You card is tapped through to the concert detail.
/// `tier` is "loved" or "station" — the recommendation kind only, never the
/// concert or the liked artist that surfaced it.
@AnalyticsEvent
public struct ForYouCardTapped {
    public let tier: String

    public init(tier: String) {
        self.tier = tier
    }
}

/// Event fired when the listener dismisses a For You card via its "Not interested"
/// menu. `tier` is "loved" or "station" — the recommendation kind only, never the
/// concert or the liked artist that surfaced it.
@AnalyticsEvent
public struct ForYouCardDismissed {
    public let tier: String

    public init(tier: String) {
        self.tier = tier
    }
}

// MARK: - Sharing (#536)

/// Event fired when the listener starts sharing a concert — invoking the detail
/// view's share button or the row's "Share Show" context action. `surface` is the
/// originating affordance ("detail" or "row") and is the event's only property:
/// the shared link resolves the show server-side, so no concert or artist id ever
/// rides along, per the On Tour privacy invariant.
@AnalyticsEvent
public struct ConcertShareInitiated {
    public let surface: String

    public init(surface: String) {
        self.surface = surface
    }
}

/// Event fired when a shared show link opens the app and the arrival path
/// finishes resolving it (#537). `source` is the link form — "universalLink"
/// (`wxyc.org/shows/<id>`, a friend tapped a public link) or "scheme"
/// (`wxyc://concert/<id>`, an app-owned surface). `resolution` is the ladder rung
/// that resolved it — "window" (already in the loaded list), "byID" (fetched
/// individually), or "missed" (couldn't be found). Both are low-cardinality
/// labels; the concert id never rides along — which show a listener opened is
/// taste data that stays on the device, per the On Tour privacy invariant.
@AnalyticsEvent
public struct ConcertDeepLinkOpened {
    public let source: String
    public let resolution: String

    public init(source: String, resolution: String) {
        self.source = source
        self.resolution = resolution
    }
}

// MARK: - Add to Calendar (#538)

/// Event fired when the listener commits an "Add to Calendar" — i.e. the
/// EventKit editor reports a saved event, not merely on tapping the affordance.
/// `surface` is the originating affordance ("detail" or "row"); `timing` is the
/// event shape the concert produced — "timed" (a known start instant) or
/// "allDay" (date-only or doors-only). Both are low-cardinality labels: no
/// concert, artist, or calendar identity ever rides along, per the On Tour
/// privacy invariant.
@AnalyticsEvent
public struct ConcertCalendarAdded {
    public let surface: String
    public let timing: String

    public init(surface: String, timing: String) {
        self.surface = surface
        self.timing = timing
    }
}

// MARK: - Siri / Spotlight (OT-C2, #625)

/// Event fired when the "What WXYC artists are touring near me?" Siri intent
/// (`ToursNearMe`) finishes answering. `dateWindow` is the selected window's
/// raw case name ("tonight" / "thisWeekend" / "next7Days"); `resultCount` is
/// the number of concerts returned. Neither carries a concert or artist
/// identity, and the on-device liked-artist intersection that may have
/// shaped `resultCount` never appears here at all — per the On Tour privacy
/// invariant this file's header documents.
@AnalyticsEvent
public struct ToursNearMeIntentAnswered {
    public let dateWindow: String
    public let resultCount: Int

    public init(dateWindow: String, resultCount: Int) {
        self.dateWindow = dateWindow
        self.resultCount = resultCount
    }
}

// MARK: - Intent tier

/// The band-and-show payload every On Tour *intent* event carries.
///
/// Factored out rather than repeated per event because the key names are
/// load-bearing *across* events, not just within one. `artist` and `artist_id`
/// have to match ``SongLikeToggled``'s exactly, so a liked-artist cohort joins
/// against intent without aliasing; and every intent event has to spell them
/// the same way as every other, so a ticket tap is computable as a rate over
/// the ``ConcertDetailViewed`` that preceded it. Both are silent failures — a
/// misspelled key produces a query that runs and returns nothing — so the
/// definition lives in exactly one place.
///
/// `artistId` is `nil` for a headliner the WXYC catalog doesn't know (a local
/// opener), and is **omitted** from the payload rather than sent as null. That
/// omission is why the events composing this are hand-written rather than
/// `@AnalyticsEvent`-derived: the macro emits a flat dictionary literal with no
/// nil handling, so an `Int?` would serialize as an `Optional`-wrapped `Any`.
/// Same reasoning, same shape as `SongLikeToggled`.
public struct ConcertIdentity: Sendable {
    /// The billed headline name, as the listener read it on the ticket.
    public let artist: String
    /// The WXYC catalog artist id, in the same keyspace as
    /// ``SongLikeToggled/artistId``, or `nil` when the headliner is unresolved.
    public let artistId: Int?
    public let venue: String
    public let concertId: Int
    /// The `ShowStatus` raw value, so intent against an on-sale show stays
    /// separable from a tap on a sold-out or cancelled one — those open a venue
    /// page and can never become a purchase.
    public let status: String

    public init(
        artist: String,
        artistId: Int? = nil,
        venue: String,
        concertId: Int,
        status: String
    ) {
        self.artist = artist
        self.artistId = artistId
        self.venue = venue
        self.concertId = concertId
        self.status = status
    }

    /// The five shared keys, ready for an event to add its own affordance name to.
    public var properties: [String: Any] {
        var props: [String: Any] = [
            "artist": artist,
            "venue": venue,
            "concert_id": concertId,
            "status": status,
        ]
        if let artistId { props["artist_id"] = artistId }
        return props
    }
}

/// Event fired when a concert detail is presented, whichever path opened it.
///
/// The denominator for the rest of the intent tier. Every other action a
/// listener can take on a show — tickets, directions, calendar, share — is only
/// interpretable as a rate over the views that preceded it, and until this
/// event existed there was no such rate: ``ForYouCardTapped`` covered the shelf
/// path alone, so a tap arriving from a list row or a shared link had nothing
/// to divide by.
///
/// `source` is the arrival path: `"row"` (the On Tour list), `"for_you"` (the
/// "Heard on WXYC" shelf), or `"deep_link"` (a shared link or an app-owned
/// URL). Kept as a separate vocabulary from ``ConcertTicketsTapped/surface`` on
/// purpose — a `surface` names the affordance that was pressed, a `source`
/// names how the listener reached the screen holding it.
public struct ConcertDetailViewed: AnalyticsEvent {
    /// Stated rather than left to `AnalyticsEvent`'s default, which derives the
    /// same string but recomputes the snake-case conversion on every capture —
    /// the `SongLikeToggled` precedent.
    public static let name = "concert_detail_viewed"

    public let concert: ConcertIdentity
    public let source: String

    public var properties: [String: Any]? {
        var props = concert.properties
        props["source"] = source
        return props
    }

    public init(concert: ConcertIdentity, source: String) {
        self.concert = concert
        self.source = source
    }
}

/// Event fired when a listener taps the outbound box-office CTA for a show —
/// "Get Tickets", "RSVP", or whichever wording ``BoxOfficeTicketPresenter``
/// chose for the status. Fires on the tap, not on a confirmed purchase: WXYC
/// hands off to the venue and never learns what happened next.
///
/// The first On Tour event to carry band identity, and the reason this file's
/// header describes two tiers.
///
/// `surface` is which affordance was tapped — `"detail"` (the On Tour concert
/// detail's ticket), `"playcut_detail"` (the same ticket embedded under a
/// playcut, reached from the playlist rather than the On Tour tab), or `"row"`
/// (the On Tour list row's context menu).
public struct ConcertTicketsTapped: AnalyticsEvent {
    /// Stated rather than derived, as above.
    public static let name = "concert_tickets_tapped"

    public let concert: ConcertIdentity
    public let surface: String

    public var properties: [String: Any]? {
        var props = concert.properties
        props["surface"] = surface
        return props
    }

    public init(concert: ConcertIdentity, surface: String) {
        self.concert = concert
        self.surface = surface
    }
}
