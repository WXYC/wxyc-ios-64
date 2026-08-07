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
/// 2. ``repairs(for:playlists:)`` — the repair path (#812). The flowsheet feed
///    serves a real, renderable row carrying only its base columns for roughly
///    two seconds after insert. A card opened in that window used to latch the
///    pre-enrichment snapshot forever, because `PlaycutDetailView` held a
///    `let playcut` value and resolved it exactly once. This re-resolves it
///    from the store's row once that row's enrichment lands.
///
/// The two are independent producers and may finish in either order; the card
/// combines them through ``PlaycutMetadataResolution`` rather than letting the
/// later one win.
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

    // MARK: - Repair on enrichment (#812)

    /// Whether a card showing `playcut` has anything to gain from watching the
    /// feed for this row's enrichment.
    ///
    /// `false` in two cases, both of which would otherwise pin a playlist
    /// subscription open for a repair that can never arrive:
    ///
    /// - **Terminal.** Backend has finished with the row, so no later feed tick
    ///   can carry more than the snapshot already in hand — and #685's contract
    ///   (never spend a degradable LML round-trip on a row Backend already
    ///   finished) makes re-resolving it unwanted as well as pointless. This is
    ///   the common case: opening an older, fully-enriched row costs nothing.
    /// - **No status at all.** `nil` means the v1 API, a feed decoded before
    ///   #280 added `metadata_status`, or a synthesized playcut with no
    ///   live-feed counterpart (the Liked tab's `LikedSongSnapshot.toPlaycut()`
    ///   hardcodes id 0). None of them will ever produce a status transition.
    public static func shouldObserveEnrichment(for playcut: Playcut) -> Bool {
        guard let status = playcut.metadataStatus else { return false }
        return !status.isTerminal
    }

    /// Repaired metadata for `playcut`: at most one element, produced the first
    /// time the store reports this row in a terminal enrichment state.
    ///
    /// `playlists` is `PlaylistService.updates()`. Reading the raw snapshots
    /// rather than `terminalMetadataTransitions()` is deliberate. That stream
    /// discards its first snapshot to seed a per-subscriber baseline, which is
    /// correct for #443's Spotlight consumer but structurally blind to the
    /// race this repair exists for: the cover transition plus task scheduling
    /// costs a few hundred milliseconds inside a ~2 second window, so the row
    /// can reach terminal between row-tap and subscription. The baseline would
    /// then record it as already-terminal and no transition would ever fire.
    /// Reconciling against the store's *current* row closes that hole without
    /// touching semantics #443 depends on.
    ///
    /// The #685 budget is respected structurally rather than by care: the row
    /// is terminal by the time it is yielded, so ``resolve(for:)`` takes the
    /// inline branch and issues **zero** `/proxy/metadata/album` requests. The
    /// stream finishes after one repair, so no amount of further polling can
    /// re-fire it.
    ///
    /// Matching is by `id`, so a sibling row landing its enrichment — the
    /// common case, since the feed enriches every new track — never repaints
    /// this card. Enforces ``shouldObserveEnrichment(for:)`` itself: a caller
    /// that skips the check gets an immediately-finished stream rather than a
    /// live subscription.
    public func repairs(
        for playcut: Playcut,
        playlists: AsyncStream<Playlist>
    ) -> AsyncStream<PlaycutMetadata> {
        AsyncStream { continuation in
            guard Self.shouldObserveEnrichment(for: playcut) else {
                continuation.finish()
                return
            }

            let task = Task {
                for await playlist in playlists {
                    guard let row = playlist.playcuts.first(where: { $0.id == playcut.id }),
                          row.metadataStatus?.isTerminal == true
                    else { continue }

                    continuation.yield(await resolve(for: row))
                    break
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
