//
//  PlaycutMetadataResolver.swift
//  Metadata
//
//  Resolves the playcut detail card's metadata: builds the inline V2 flowsheet
//  metadata, decides inline-vs-proxy off the row's enrichment lifecycle, and
//  re-resolves a card that was opened before its row finished enriching.
//
//  Created by Jake Bromberg on 08/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Playlist

/// The detail card's metadata resolution policy, lifted out of
/// `PlaycutDetailView` so it is reachable from package unit tests.
///
/// Two responsibilities, both previously inlined in the view:
///
/// 1. ``resolve(for:)`` — the one-shot decision the card makes on appear:
///    render straight from the row's inline V2 fields when Backend has finished
///    enrichment, else fall through to `/proxy/metadata/album`.
/// 2. ``reresolutions(for:transitions:)`` — the repair path (#812). The
///    flowsheet feed serves a real, renderable row carrying only its base
///    columns for roughly two seconds after insert. A card opened in that window
///    used to latch the pre-enrichment snapshot forever, because
///    `PlaycutDetailView` held a `let playcut` value and resolved it exactly
///    once. This re-resolves it when the row's own enrichment lands.
public struct PlaycutMetadataResolver: Sendable {
    private let service: PlaycutMetadataService

    public init(service: PlaycutMetadataService) {
        self.service = service
    }

    // MARK: - Inline construction

    /// Builds inline metadata from the V2 flowsheet row, or `nil` when the row
    /// carries none (``Playcut/hasV2Metadata``).
    ///
    /// This field list must be kept in sync by hand with two other
    /// enumerations of the same 12 inline fields: `Playcut`'s `CodingKeys`/
    /// `init(from:)` (`Shared/Playlist/Sources/Playlist/PlaylistEntry.swift`)
    /// and `Playcut.hasV2Metadata`'s OR-chain in the same file. There's no
    /// compiler-enforced link — #685 itself patched one drift here
    /// (`artworkURL` was missing from this construction).
    ///
    /// `criticReviews` below is NOT one of the 12 — like `artistId` and
    /// `upcomingShow`, it's excluded from `hasV2Metadata`'s predicate (see
    /// that doc comment) — but it still needs to ride through to
    /// ``AlbumMetadata`` here so a terminal row's `ReviewsSection` renders
    /// from feed data alone (#695).
    public static func inlineMetadata(for playcut: Playcut) -> PlaycutMetadata? {
        guard playcut.hasV2Metadata else { return nil }

        return PlaycutMetadata(
            artist: ArtistMetadata(bio: playcut.artistBio, wikipediaURL: playcut.artistWikipediaURL),
            album: AlbumMetadata(
                label: playcut.labelName,
                releaseYear: playcut.releaseYear,
                discogsURL: playcut.discogsURL,
                genres: playcut.genres,
                styles: playcut.styles,
                artworkURL: playcut.artworkURL,
                criticReviews: playcut.criticReviews,
                // Like criticReviews above, discogsUnavailable isn't one of
                // the 12 hasV2Metadata fields (see that predicate's doc
                // comment) but still rides along here so the caller's
                // artwork-fetch gate can see it (#390).
                discogsUnavailable: playcut.discogsUnavailable,
                discogsUnavailableNote: playcut.discogsUnavailableNote
            ),
            streaming: StreamingLinks(
                spotifyURL: playcut.spotifyURL,
                appleMusicURL: playcut.appleMusicURL,
                youtubeMusicURL: playcut.youtubeMusicURL,
                bandcampURL: playcut.bandcampURL,
                soundcloudURL: playcut.soundcloudURL
            )
        )
    }

    // MARK: - Resolution

    /// Resolves the metadata to render for `playcut`.
    ///
    /// Explicit branch on the row's server-side enrichment lifecycle (#270),
    /// replacing the old `hasV2Metadata`-only heuristic at this call site.
    /// `enrichedMatch`/`enrichedNoMatch`/`failedNoRetry` are terminal — Backend
    /// has already finished (or given up on) enrichment — so this branch renders
    /// straight from the inline V2 flowsheet fields and never calls
    /// `PlaycutMetadataService.fetchMetadata`: no outbound
    /// `/proxy/metadata/album` request is possible on this path.
    /// `pending`/`enriching` rows are still being enriched server-side, and
    /// `nil` covers V1 rows, pre-Epic-C Backend deploys, and feeds decoded
    /// before #280's `metadata_status` field existed — both fall back to the
    /// metadata service.
    public func resolve(for playcut: Playcut) async -> PlaycutMetadata {
        let inline = Self.inlineMetadata(for: playcut)

        switch playcut.metadataStatus {
        case .enrichedMatch, .enrichedNoMatch, .failedNoRetry:
            return inline ?? .empty
        case .pending, .enriching, nil:
            return await service.fetchMetadata(for: playcut, inline: inline)
        }
    }

    // MARK: - Re-resolution on enrichment (#812)

    /// Whether a card showing `playcut` has anything to gain from watching the
    /// feed for this row's enrichment.
    ///
    /// `false` once the row is terminal: Backend has finished with it, so no
    /// later feed tick can carry more than the snapshot already in hand, and
    /// #685's contract (never spend a degradable LML round-trip on a row
    /// Backend already finished) makes re-resolving it pointless as well as
    /// unwanted. Callers use this to skip subscribing at all, so the common
    /// case — opening an older, fully-enriched row — costs nothing.
    public func shouldObserveEnrichment(for playcut: Playcut) -> Bool {
        playcut.metadataStatus?.isTerminal != true
    }

    /// Re-resolved metadata for `playcut`, one element per time *this* row
    /// transitions into a terminal enrichment state.
    ///
    /// `transitions` is `PlaylistService.terminalMetadataTransitions()`, which
    /// already yields only on a transition *into* terminal (never a re-broadcast
    /// of an already-terminal status, and never a terminal → terminal change),
    /// so the #685 budget is respected structurally: at most one repair per row,
    /// and because the row arrives terminal, ``resolve(for:)`` takes the inline
    /// branch and issues **zero** `/proxy/metadata/album` requests.
    ///
    /// Filtered by `id` so a sibling row landing its enrichment — the common
    /// case, since the feed enriches every new track — never repaints this card.
    /// A synthesized playcut with no live-feed counterpart (the Liked tab's
    /// `LikedSongSnapshot.toPlaycut()` hardcodes id 0) simply never matches.
    public func reresolutions(
        for playcut: Playcut,
        transitions: AsyncStream<Playcut>
    ) -> AsyncStream<PlaycutMetadata> {
        AsyncStream { continuation in
            let task = Task {
                for await enriched in transitions where enriched.id == playcut.id {
                    continuation.yield(await resolve(for: enriched))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
