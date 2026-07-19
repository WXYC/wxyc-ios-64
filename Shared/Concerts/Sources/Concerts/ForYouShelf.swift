//
//  ForYouShelf.swift
//  Concerts
//
//  The on-device "For You" recommendation engine for the On Tour tab
//  (WXYC/wxyc-ios-64#493). Given the fetched concert window and the listener's
//  liked artists, it builds the ordered shelf of cards pinned above the
//  date-ordered list: loved shows first (the headliner is a liked artist), then
//  similar shows (a liked artist is an affinity neighbor of the headliner),
//  ranked by weight and capped to tame noise, then station-affinity shows (the
//  headliner is in heavy WXYC rotation) — the one tier that needs no likes, so a
//  cold-start listener still sees a shelf (WXYC/wxyc-ios-64#549).
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
/// id-keyed ``Concert/headliningArtistId`` / ``SimilarArtist/artistId`` fields.
///
/// The ``name`` is the display name from the local likes store; it supplies the
/// shelf's reason line ("Because you like Stereolab") so the recommendation is
/// legible without the server ever sending — or learning — the listener's taste.
public struct LikedArtist: Sendable, Equatable, Hashable, Identifiable {

    /// WXYC catalog artist id, the keyspace shared with ``Concert/headliningArtistId``.
    public let id: Int

    /// The locally-stored display name, used verbatim in the reason line.
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// One card on the For You shelf: a concert the listener is likely to care about,
/// the tier that surfaced it, and the liked artist to name in its reason line.
public struct ForYouRecommendation: Sendable, Equatable, Identifiable {

    /// Why a concert made the shelf. Ordered by descending personal confidence:
    /// ``loved`` (the listener's own artist) outranks ``similar`` (a taste
    /// neighbor) outranks ``stationAffinity`` (a station-wide signal, no personal
    /// tie at all).
    public enum Tier: Sendable, Equatable {
        /// The concert's headliner is itself a liked artist.
        case loved
        /// A liked artist is among the headliner's affinity neighbors; the
        /// associated value is that neighbor's affinity ``SimilarArtist/weight``,
        /// the key the similar tier ranks and caps on.
        case similar(weight: Double)
        /// The headliner is not in the listener's taste graph, but is in heavy
        /// WXYC rotation: its all-time resolved flowsheet play count clears the
        /// station floor. The associated value is that ``Concert/stationPlays``
        /// count, the key the station tier ranks on. Because it is a genuine global
        /// scalar (not per-list normalized like ``similar``'s weight) cross-concert
        /// ranking is valid. Ranked below ``similar`` — a personal signal always
        /// outranks the station-wide one — and it is the only tier that can surface
        /// a card with no likes, so it fills the cold-start shelf.
        case stationAffinity(plays: Int)

        /// The tier's stable analytics name — `"loved"`, `"similar"`, or
        /// `"station"`. The associated value (weight / play count) is deliberately
        /// dropped: the tier-only On Tour events record the recommendation *kind*,
        /// never a score or any identity.
        public var analyticsName: String {
            switch self {
            case .loved: "loved"
            case .similar: "similar"
            case .stationAffinity: "station"
            }
        }
    }

    /// The recommended concert.
    public let concert: Concert

    /// The tier that surfaced this card.
    public let tier: Tier

    /// The liked artist named in the reason line. For a loved card this is the
    /// headliner; for a similar card it's the highest-weight intersecting liked
    /// neighbor. Sourced from the local likes store, never the wire.
    public let reasonArtistName: String

    /// Stable per concert, so the shelf can key a `ForEach` on it.
    public var id: Int { concert.id }

    public init(concert: Concert, tier: Tier, reasonArtistName: String) {
        self.concert = concert
        self.tier = tier
        self.reasonArtistName = reasonArtistName
    }
}

/// The number of For You cards in each tier of a built shelf. Feeds the
/// shelf-impression analytics — volume without identity, per the On Tour privacy
/// invariant. Every card falls in exactly one bucket, so the three counts sum to
/// the shelf's card count.
public struct ForYouTierCounts: Sendable, Equatable {

    /// Cards whose headliner is itself a liked artist.
    public let loved: Int

    /// Cards surfaced by a liked affinity-neighbor of the headliner.
    public let similar: Int

    /// Cards surfaced by the station-wide play-affinity signal, with no personal
    /// tie — the cold-start tier. Kept a separate bucket so it is never folded
    /// into ``similar`` (WXYC/wxyc-ios-64#551).
    public let stationAffinity: Int

    public init(loved: Int, similar: Int, stationAffinity: Int) {
        self.loved = loved
        self.similar = similar
        self.stationAffinity = stationAffinity
    }
}

public extension Sequence where Element == ForYouRecommendation {

    /// The per-tier card counts of this shelf, for the shelf-impression analytics.
    /// Buckets each card by its own ``ForYouRecommendation/Tier`` — a station card
    /// counts as station, never as similar.
    var tierCounts: ForYouTierCounts {
        var loved = 0, similar = 0, station = 0
        for recommendation in self {
            switch recommendation.tier {
            case .loved: loved += 1
            case .similar: similar += 1
            case .stationAffinity: station += 1
            }
        }
        return ForYouTierCounts(loved: loved, similar: similar, stationAffinity: station)
    }
}

/// The pure For You recommendation engine.
public enum ForYouShelf {

    /// Builds the ordered For You shelf from the fetched concert window, the
    /// listener's liked artists, and the station-affinity signal.
    ///
    /// Ordering is by descending personal confidence: loved cards first (in the
    /// input window order — the fetched window is `starts_on` ascending, so this is
    /// chronological), then similar cards ranked by weight descending and capped to
    /// `similarCap`, then station-affinity cards ranked by play count descending and
    /// capped to `stationCap`. A concert is deduped to its highest qualifying tier:
    /// one that is both loved and similar appears once as loved, and one that is a
    /// personal match (loved *or* similar) is never re-surfaced as a station card.
    ///
    /// Unlike the likes tiers, the station tier needs **no** likes: it clears the
    /// cold-start case where a listener with zero id-bearing likes would otherwise
    /// see an empty shelf. Returns `[]` only when nothing qualifies on any tier.
    ///
    /// - Parameters:
    ///   - concerts: the fetched window. Loved cards preserve this order.
    ///   - likedArtists: the id-bearing liked artists; each ``LikedArtist/name``
    ///     supplies its reason line. May be empty (cold start) — the station tier
    ///     still fills the shelf.
    ///   - similarCap: the maximum number of similar-tier cards. Injected rather
    ///     than read from the flag provider so this stays deterministic under
    ///     test; the app passes the PostHog-tuned value (local default 3). A
    ///     non-positive cap drops every similar card while leaving loved cards
    ///     untouched.
    ///   - relativeFloor: the list-relative noise gate. A liked neighbor only
    ///     counts as a similar match when its weight is at least
    ///     `relativeFloor × (that concert's top neighbor weight)` — so a
    ///     weakly-related liked artist buried in a dense neighborhood doesn't
    ///     surface a card, while the same absolute weight in a sparse
    ///     neighborhood still can. `0` disables the gate (any liked neighbor
    ///     counts); the default `0.5` keeps neighbors within half the list's top.
    ///   - stationFloor: the absolute play-count threshold a headliner's
    ///     ``Concert/stationPlays`` must reach to earn a station card. An absolute
    ///     floor (not a window-relative percentile) so "heavy rotation" stays a
    ///     stable claim as the window paginates. Injected; the app passes the
    ///     PostHog-tuned value (local default `50`, the data-backed cliff).
    ///   - stationCap: the maximum number of station-tier cards. Injected like
    ///     `similarCap`; a non-positive cap drops every station card. **Defaults to
    ///     `0` (tier off)** so a caller that doesn't opt in keeps the likes-only
    ///     shelf; the app passes the flag-tuned value to turn the tier on.
    /// - Returns: the ordered shelf, `loved + cappedSimilar + cappedStation`.
    ///
    /// - Note: ``SimilarArtist/weight`` is type-max normalized per source artist,
    ///   so it is only strictly comparable *within* one concert's neighbor list.
    ///   `relativeFloor` keeps the qualify decision list-relative rather than
    ///   using an absolute threshold that would behave differently for dense- vs
    ///   sparse-neighborhood headliners (WXYC/semantic-index#354 review). The
    ///   per-concert reason pick (the max intersecting weight) is on solid ground;
    ///   the cross-concert similar ranking treats the representative weight as a
    ///   coarse proxy — acceptable for a top-N shelf cap. ``Concert/stationPlays``,
    ///   by contrast, *is* a global scalar, so ranking station cards across
    ///   concerts by raw play count is exact.
    public static func recommendations(
        concerts: [Concert],
        likedArtists: [LikedArtist],
        similarCap: Int,
        relativeFloor: Double = 0.5,
        stationFloor: Int = 50,
        stationCap: Int = 0
    ) -> [ForYouRecommendation] {
        // First like of an id wins, so the reason-line name is stable if the
        // store somehow carries the same id twice.
        let likedNameByID = Dictionary(
            likedArtists.map { ($0.id, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        let likedIDs = Set(likedNameByID.keys)

        // `claimedConcertIDs` accumulates every concert already surfaced by a
        // higher tier, so each lower tier only considers what's left — the dedup
        // "keep the higher tier" rule, by construction. Both likes tiers are
        // naturally empty when `likedIDs` is empty (cold start), leaving the
        // station tier to fill the shelf on its own.
        var claimedConcertIDs: Set<Int> = []

        // Loved: headliner is itself liked. Preserve input (chronological) order.
        var loved: [ForYouRecommendation] = []
        for concert in concerts {
            guard let artistID = concert.headliningArtistId, likedIDs.contains(artistID) else { continue }
            loved.append(ForYouRecommendation(
                concert: concert,
                tier: .loved,
                // artistID ∈ likedIDs ⇒ the name is present; the fallback is inert.
                reasonArtistName: likedNameByID[artistID] ?? concert.headlineName
            ))
            claimedConcertIDs.insert(concert.id)
        }

        // Similar: a liked artist is an affinity neighbor of the (non-loved)
        // headliner, and clears the list-relative noise floor. The representative
        // neighbor is the highest-weight qualifying liked one. A concert that
        // qualifies here is claimed even if the `similarCap` later drops it, so a
        // personal match is never demoted to a station card.
        var similar: [ForYouRecommendation] = []
        for concert in concerts where !claimedConcertIDs.contains(concert.id) {
            guard let representative = qualifyingLikedNeighbor(
                in: concert, likedIDs: likedIDs, relativeFloor: relativeFloor
            ) else { continue }
            similar.append(ForYouRecommendation(
                concert: concert,
                tier: .similar(weight: representative.weight),
                reasonArtistName: likedNameByID[representative.artistId] ?? concert.headlineName
            ))
            claimedConcertIDs.insert(concert.id)
        }

        // Rank the similar pool by representative weight (desc); tie-break on the
        // soonest date then concert id for a deterministic order; then cap.
        similar.sort { lhs, rhs in
            let lw = similarWeight(lhs), rw = similarWeight(rhs)
            if lw != rw { return lw > rw }
            if lhs.concert.startsOn != rhs.concert.startsOn { return lhs.concert.startsOn < rhs.concert.startsOn }
            return lhs.concert.id < rhs.concert.id
        }
        let cappedSimilar = similar.prefix(max(0, similarCap))

        // When the station tier is off — a non-positive cap, which is the default,
        // so this is the common flag-off production path — skip the whole
        // pool-build and sort. The station tier is terminal, so its would-be claims
        // feed no later tier, and `prefix(max(0, stationCap))` would discard every
        // card anyway; computing them first is pure wasted work on every render.
        guard stationCap > 0 else { return loved + cappedSimilar }

        // Station affinity: the headliner has no personal tie but is in heavy WXYC
        // rotation — its play count clears the absolute floor. No likes required,
        // so this is the tier that fills the cold-start shelf.
        var station: [ForYouRecommendation] = []
        for concert in concerts where !claimedConcertIDs.contains(concert.id) {
            guard let plays = concert.stationPlays, plays >= stationFloor else { continue }
            station.append(ForYouRecommendation(
                concert: concert,
                tier: .stationAffinity(plays: plays),
                reasonArtistName: concert.headlineName
            ))
        }

        // Rank by play count (desc) — a valid cross-concert ordering since the
        // count is a global scalar; tie-break on soonest date then concert id for a
        // deterministic order; then cap.
        station.sort { lhs, rhs in
            let lp = stationPlays(lhs), rp = stationPlays(rhs)
            if lp != rp { return lp > rp }
            if lhs.concert.startsOn != rhs.concert.startsOn { return lhs.concert.startsOn < rhs.concert.startsOn }
            return lhs.concert.id < rhs.concert.id
        }
        let cappedStation = station.prefix(max(0, stationCap))

        return loved + cappedSimilar + cappedStation
    }

    /// The highest-weight liked neighbor in `concert`'s affinity list that also
    /// clears the list-relative floor, or `nil` when no liked neighbor qualifies.
    ///
    /// The floor is measured against the list's own top weight (over *all*
    /// neighbors, not just liked ones), so it stays comparable within the list —
    /// the property ``SimilarArtist/weight`` guarantees. Because qualification
    /// gates on the single highest-weight liked neighbor, once that one clears the
    /// floor it is also the representative; ties on weight break on the smaller
    /// artist id, so the reason line is deterministic.
    private static func qualifyingLikedNeighbor(
        in concert: Concert,
        likedIDs: Set<Int>,
        relativeFloor: Double
    ) -> SimilarArtist? {
        let neighbors = concert.similarArtists ?? []
        guard let listTop = neighbors.map(\.weight).max() else { return nil }
        guard let topLiked = neighbors
            .filter({ likedIDs.contains($0.artistId) })
            .max(by: { lhs, rhs in
                lhs.weight != rhs.weight ? lhs.weight < rhs.weight : lhs.artistId > rhs.artistId
            })
        else { return nil }
        // Inclusive floor: a neighbor exactly at `relativeFloor × listTop` counts.
        guard topLiked.weight >= relativeFloor * listTop else { return nil }
        return topLiked
    }

    /// The similar-tier ranking weight of a recommendation. Loved cards never
    /// enter the similar sort, so their inert value is never observed.
    private static func similarWeight(_ recommendation: ForYouRecommendation) -> Double {
        if case let .similar(weight) = recommendation.tier { return weight }
        return -.infinity
    }

    /// The station-tier ranking value (the headliner's WXYC play count) of a
    /// recommendation. Only station cards enter the station sort, so the inert
    /// value is never observed.
    private static func stationPlays(_ recommendation: ForYouRecommendation) -> Int {
        if case let .stationAffinity(plays) = recommendation.tier { return plays }
        return .min
    }
}
