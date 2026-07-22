//
//  ForYouShelf.swift
//  Concerts
//
//  The on-device "Heard on WXYC" recommendation engine for the On Tour tab
//  (WXYC/wxyc-ios-64#493). Given the fetched concert window and the listener's
//  liked artists, it builds the ordered shelf of cards pinned above the
//  date-ordered list: loved shows first (the headliner is a liked artist), then
//  station-recommended shows (the station itself vouches for the show,
//  WXYC/wxyc-ios-64#577) — the one tier that needs no likes, so a cold-start
//  listener still sees a shelf.
//
//  Pure by design: the whole match/rank/cap computation is a value-in/value-out
//  function (the ConcertFilterState recipe). Likes arrive as plain values and the
//  cap arrives as a parameter — the SwiftData likes store and the PostHog
//  feature-flag read both live in the app target, so this logic stays testable
//  without either. Every intersection happens here, on-device: no taste signal
//  is ever sent to the server, which is the privacy invariant behind the whole
//  feature.
//
//  Created by Jake Bromberg on 07/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A liked artist that carries a resolved WXYC catalog id — the only likes that
/// can take part in For You matching, since the id-less likes can't intersect the
/// id-keyed ``Concert/headliningArtistId`` field.
public struct LikedArtist: Sendable, Equatable, Hashable, Identifiable {

    /// WXYC catalog artist id, the keyspace shared with ``Concert/headliningArtistId``.
    public let id: Int

    /// The locally-stored display name, carried for the caller's convenience. The
    /// engine matches on ``id`` alone; the name never reaches the server.
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// One card on the For You shelf: a concert the listener is likely to care about,
/// and the tier that surfaced it.
public struct ForYouRecommendation: Sendable, Equatable, Identifiable {

    /// Why a concert made the shelf. Ordered by descending personal confidence:
    /// ``loved`` (the listener's own artist) outranks ``stationRecommended``
    /// (a station-wide signal, no personal tie at all).
    public enum Tier: Sendable, Equatable {
        /// The concert's headliner is itself a liked artist.
        case loved
        /// The show is not in the listener's likes, but the station itself
        /// recommends it: ``Concert/stationRecommended`` is true
        /// (WXYC/wxyc-ios-64#577, replacing the play-count affinity tier of #549).
        /// A boolean carries no rank, so within the tier shows order by concert
        /// date ascending — soonest first. Ranked below ``loved`` — a personal
        /// signal always outranks the station-wide one — and it is the only tier
        /// that can surface a card with no likes, so it fills the cold-start shelf.
        case stationRecommended

        /// The tier's stable analytics name — `"loved"` or `"station"`. The
        /// `"station"` name deliberately survives the play-count → recommended
        /// rewrite (#577): the PostHog funnels keyed on it must not break over a
        /// rename. The tier-only On Tour events record the recommendation *kind*,
        /// never a score or any identity.
        public var analyticsName: String {
            switch self {
            case .loved: "loved"
            case .stationRecommended: "station"
            }
        }
    }

    /// The recommended concert.
    public let concert: Concert

    /// The tier that surfaced this card.
    public let tier: Tier

    /// Stable per concert, so the shelf can key a `ForEach` on it.
    public var id: Int { concert.id }

    public init(concert: Concert, tier: Tier) {
        self.concert = concert
        self.tier = tier
    }
}

/// The number of For You cards in each tier of a built shelf. Feeds the
/// shelf-impression analytics — volume without identity, per the On Tour privacy
/// invariant. Every card falls in exactly one bucket, so the two counts sum to
/// the shelf's card count.
public struct ForYouTierCounts: Sendable, Equatable {

    /// Cards whose headliner is itself a liked artist.
    public let loved: Int

    /// Cards surfaced by the station-wide recommendation signal, with no personal
    /// tie — the cold-start tier.
    public let stationRecommended: Int

    public init(loved: Int, stationRecommended: Int) {
        self.loved = loved
        self.stationRecommended = stationRecommended
    }
}

public extension Sequence where Element == ForYouRecommendation {

    /// The per-tier card counts of this shelf, for the shelf-impression analytics.
    /// Buckets each card by its own ``ForYouRecommendation/Tier``.
    var tierCounts: ForYouTierCounts {
        var loved = 0, station = 0
        for recommendation in self {
            switch recommendation.tier {
            case .loved: loved += 1
            case .stationRecommended: station += 1
            }
        }
        return ForYouTierCounts(loved: loved, stationRecommended: station)
    }
}

/// The pure For You recommendation engine.
public enum ForYouShelf {

    /// Builds the ordered For You shelf from the fetched concert window, the
    /// listener's liked artists, and the station-recommended signal.
    ///
    /// Ordering is by descending personal confidence: loved cards first (in the
    /// input window order — the fetched window is `starts_on` ascending, so this is
    /// chronological), then station-recommended cards ordered by concert date
    /// ascending (soonest first — the signal is a boolean, so there is no scalar to
    /// rank on) and capped to `stationCap`. A concert is deduped to its highest
    /// qualifying tier: one that is both loved and station-recommended appears once,
    /// as loved.
    ///
    /// Unlike the loved tier, the station tier needs **no** likes: it clears the
    /// cold-start case where a listener with zero id-bearing likes would otherwise
    /// see an empty shelf. Returns `[]` only when nothing qualifies on any tier.
    ///
    /// - Parameters:
    ///   - concerts: the fetched window. Loved cards preserve this order.
    ///   - likedArtists: the id-bearing liked artists. May be empty (cold start) —
    ///     the station tier still fills the shelf.
    ///   - stationCap: the maximum number of station-tier cards. A non-positive cap
    ///     drops every station card. **Defaults to `0` (tier off)** so a caller that
    ///     doesn't opt in keeps the likes-only shelf; the app passes the flag-tuned
    ///     value to turn the tier on.
    ///   - dismissedConcertIDs: concerts the listener tapped "Not interested" on.
    ///     Filtered out of the window up front, so a dismissed concert can surface
    ///     no card on any tier. Defaults to empty (behavior-neutral): the shelf is
    ///     identical to the pre-dismiss engine when nothing has been dismissed.
    /// - Returns: the ordered shelf, `loved + cappedStation`.
    public static func recommendations(
        concerts: [Concert],
        likedArtists: [LikedArtist],
        stationCap: Int = 0,
        dismissedConcertIDs: Set<Int> = []
    ) -> [ForYouRecommendation] {
        // Drop dismissed concerts up front so a "Not interested" show can surface
        // no card on any tier. Skipped entirely when nothing is dismissed — the
        // behavior-neutral common path.
        let concerts = dismissedConcertIDs.isEmpty
            ? concerts
            : concerts.filter { !dismissedConcertIDs.contains($0.id) }

        // Matching is by id alone; duplicate ids in the store collapse in the set.
        let likedIDs = Set(likedArtists.map(\.id))

        // Loved: headliner is itself liked. Preserve input (chronological) order.
        // Each loved concert is recorded in `claimedConcertIDs` so the station tier
        // can't re-surface it — the dedup "keep the higher tier" rule.
        var claimedConcertIDs: Set<Int> = []
        var loved: [ForYouRecommendation] = []
        for concert in concerts {
            guard let artistID = concert.headliningArtistId, likedIDs.contains(artistID) else { continue }
            loved.append(ForYouRecommendation(concert: concert, tier: .loved))
            claimedConcertIDs.insert(concert.id)
        }

        // When the station tier is off — a non-positive cap, which is the default,
        // so this is the common flag-off production path — the shelf is loved-only;
        // skip the pool build and sort entirely.
        guard stationCap > 0 else { return loved }

        // Station recommended: the show has no personal tie but the station itself
        // vouches for it (#577). No likes required, so this is the tier that fills
        // the cold-start shelf.
        var station: [ForYouRecommendation] = []
        for concert in concerts where !claimedConcertIDs.contains(concert.id) {
            guard concert.stationRecommended else { continue }
            station.append(ForYouRecommendation(concert: concert, tier: .stationRecommended))
        }

        // A boolean signal carries no rank, so order by concert date ascending
        // (soonest first); tie-break on concert id for a deterministic order; then
        // cap.
        station.sort { lhs, rhs in
            if lhs.concert.startsOn != rhs.concert.startsOn { return lhs.concert.startsOn < rhs.concert.startsOn }
            return lhs.concert.id < rhs.concert.id
        }

        return loved + station.prefix(max(0, stationCap))
    }
}
