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

/// Event fired when a shared show link opens the app and the arrival path
/// finishes resolving it (#537). `source` is the link form — "universalLink"
/// (`wxyc.org/shows/<id>`, a friend tapped a public link), "webBanner" (the
/// Smart App Banner on that page), or "scheme" (`wxyc://concert/<id>`, an
/// app-owned surface: Spotlight, a shortcut). `resolution` is the ladder rung
/// that resolved it — "window" (already in the loaded list), "byID" (fetched
/// individually), or "missed" (couldn't be found).
///
/// Stays counts-only even though the rest of the arrival path now names bands,
/// and for a reason of its own rather than the general browse rule: **the
/// recipient did not choose this band, a friend did.** Attributing an inbound
/// link as the arriving listener's taste would poison exactly the affinity data
/// the intent tier exists to collect. The band is not lost — the
/// ``ConcertDetailViewed`` that follows a millisecond later carries it, with
/// honest semantics ("this person looked at this show") instead of borrowed ones.
@AnalyticsEvent
public struct ConcertDeepLinkOpened {
    public let source: String
    public let resolution: String

    public init(source: String, resolution: String) {
        self.source = source
        self.resolution = resolution
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
/// opener), and is **omitted** from the payload rather than sent as null —
/// `SongLikeToggled`'s shape, and the reason this type writes its own
/// dictionary: `@AnalyticsEvent` emits a flat literal with no nil handling, so
/// an `Int?` would serialize as an `Optional`-wrapped `Any`.
///
/// The events *composing* this can't be macro-derived either, for a different
/// reason: the macro would emit `"concert": concert` as a nested object rather
/// than flattening these five keys alongside the event's own. Hence
/// ``ConcertIntentEvent``.
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

/// An On Tour event that names the band, because the listener chose this show.
///
/// Conforming makes the composition structural rather than a convention each
/// event has to remember: the shared keys come from the default `properties`
/// below, so an event cannot ship a payload that fails to join without opting
/// out of the protocol entirely. Conformers supply only the key that names
/// their own affordance.
public protocol ConcertIntentEvent: AnalyticsEvent {
    var concert: ConcertIdentity { get }
    /// The key(s) naming this event's own affordance — `surface`, `source`, and
    /// so on. Merged over the shared identity keys.
    var affordanceProperties: [String: Any] { get }
}

extension ConcertIntentEvent {
    public var properties: [String: Any]? {
        concert.properties.merging(affordanceProperties) { _, own in own }
    }
}

/// Event fired when a concert detail is presented, whichever path opened it.
///
/// The denominator for actions taken **on the concert detail**. Tickets,
/// directions, calendar, and share are only interpretable as a rate over the
/// views that preceded them, and until this event existed there was no such
/// rate: ``ForYouCardTapped`` covered the shelf path alone, so a tap arriving
/// from a list row or a shared link had nothing to divide by.
///
/// Scope it when computing that rate. The action events also fire from two
/// surfaces that never open a detail — the row's context menu (`surface: "row"`)
/// and the keepsake ticket under a playcut (`"playcut_detail"`) — so an
/// unfiltered `concert_tickets_tapped / concert_detail_viewed` overstates
/// tap-through by counting three surfaces in the numerator against one in the
/// denominator. Filter the numerator to `surface = 'detail'`.
///
/// `source` is the arrival path: `"row"` (the On Tour list), `"for_you"` (the
/// "Heard on WXYC" shelf), or `"deep_link"` (a shared link or an app-owned
/// URL). Kept as a separate vocabulary from ``ConcertTicketsTapped/surface`` on
/// purpose — a `surface` names the affordance that was pressed, a `source`
/// names how the listener reached the screen holding it.
public struct ConcertDetailViewed: ConcertIntentEvent {
    /// Stated rather than left to `AnalyticsEvent`'s default, which derives the
    /// same string but recomputes the snake-case conversion on every capture —
    /// the `SongLikeToggled` precedent.
    public static let name = "concert_detail_viewed"

    public let concert: ConcertIdentity
    public let source: String

    public var affordanceProperties: [String: Any] { ["source": source] }

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
public struct ConcertTicketsTapped: ConcertIntentEvent {
    /// Stated rather than derived, as above.
    public static let name = "concert_tickets_tapped"

    public let concert: ConcertIdentity
    public let surface: String

    public var affordanceProperties: [String: Any] { ["surface": surface] }

    public init(concert: ConcertIdentity, surface: String) {
        self.concert = concert
        self.surface = surface
    }
}

/// Event fired when the listener starts sharing a concert — the detail view's
/// share button or the row's "Share Show" context action (`surface`).
///
/// Carries the band because choosing to send a specific show to a friend is the
/// strongest intent signal on the tab — stronger than a ticket tap, which can be
/// idle curiosity about a price. Which bands people vouch for to their friends is
/// the question the On Tour tab most wants answered.
///
/// Note the asymmetry with ``ConcertDeepLinkOpened``, which stays anonymous: the
/// sender chose the band, the recipient didn't.
public struct ConcertShareInitiated: ConcertIntentEvent {
    /// Stated rather than derived, as above.
    public static let name = "concert_share_initiated"

    public let concert: ConcertIdentity
    public let surface: String

    public var affordanceProperties: [String: Any] { ["surface": surface] }

    public init(concert: ConcertIdentity, surface: String) {
        self.concert = concert
        self.surface = surface
    }
}

/// Event fired at each step of the "Add to Calendar" flow (#538).
///
/// Replaces `concert_calendar_added`, which fired only on a completed save and
/// so could never say where the flow lost people: a tap that ended at the
/// permission alert and a tap that ended at a saved event were equally absent
/// from the data. Redesigned outright rather than supplemented because the old
/// event had never recorded a single row in PostHog — there was no history to
/// preserve, which is the only reason replacing it was cheap.
///
/// `outcome` is one of:
/// - `"requested"` — the affordance was tapped; access is being asked for. The
///   denominator: it fires whether or not permission was already granted.
/// - `"denied"` — write-only calendar access was refused.
/// - `"cancelled"` — the editor was presented and the listener backed out.
/// - `"saved"` — an event landed in the calendar.
/// - `"failed"` — access was granted but the save threw. Only the Siri path can
///   produce this; the in-app editor surfaces its own errors.
///
/// `surface` is `"detail"`, `"row"`, or `"siri"`. Siri reports through this same
/// event rather than one of its own: a listener who adds a show by voice added a
/// show, and a second event name would make "how many shows get calendared" a
/// sum that someone has to remember to write. The voice path emits one terminal
/// outcome and no `"requested"` — there is no affordance to tap.
///
/// The old event's `timing` ("timed" vs "allDay") is gone, not dropped by
/// oversight: it described the show's own date data, which is now recoverable
/// by joining `concert_id`. Carrying the band made a property redundant.
public struct ConcertCalendarFlow: ConcertIntentEvent {
    /// Stated rather than derived, as above.
    public static let name = "concert_calendar_flow"

    public let concert: ConcertIdentity
    public let surface: String
    public let outcome: String

    public var affordanceProperties: [String: Any] {
        ["surface": surface, "outcome": outcome]
    }

    public init(concert: ConcertIdentity, surface: String, outcome: String) {
        self.concert = concert
        self.surface = surface
        self.outcome = outcome
    }
}

/// Event fired when a listener opens directions to a show's venue in Maps.
///
/// Its own name rather than an action property on ``ConcertTicketsTapped``,
/// because for a free show the box-office CTA reads "RSVP" and getting
/// directions is the truer signal that someone means to attend. Named events
/// are also the only way a dying affordance stays visible: folded into a
/// shared event's volume, a tap target nobody can find any more reads as noise.
///
/// `surface` is `"detail"` (the "Where" card's Directions chip),
/// `"detail_map"` (the same card's tappable map), or `"row"` (the list row's
/// context menu). The map is split from the chip because they answer different
/// questions — the chip is a stated intent, the map is a glance that turned
/// into one — and because a map that never gets tapped should be able to say so.
public struct ConcertDirectionsTapped: ConcertIntentEvent {
    /// Stated rather than derived, as above.
    public static let name = "concert_directions_tapped"

    public let concert: ConcertIdentity
    public let surface: String

    public var affordanceProperties: [String: Any] { ["surface": surface] }

    public init(concert: ConcertIdentity, surface: String) {
        self.concert = concert
        self.surface = surface
    }
}
