//
//  PlaycutInlineMetadata.swift
//  Metadata
//
//  Branching policy for whether a v2 flowsheet row carries authoritative
//  inline metadata, or whether the consumer must fall back to a
//  `/proxy/metadata/album` fetch. Driven by the row's `metadataStatus`.
//
//  Created by Jake Bromberg on 06/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Playlist

/// Decides whether `PlaycutDetailView` (and any future inline-metadata consumer)
/// can render directly from the v2 flowsheet row's inline fields, or whether
/// it must fall back to the proxy fetch path.
///
/// Branches on ``MetadataStatus``:
/// - `enrichedMatch` / `enrichedNoMatch` / `failedNoRetry` → returns a
///   composed ``PlaycutMetadata`` from the row's inline fields. The caller
///   should render this directly and skip the proxy fetch entirely.
/// - `pending` / `enriching` / `nil` → returns `nil`. The caller falls
///   back to `PlaycutMetadataService.fetchMetadata` so the row's eventual
///   enrichment (or, for `nil`, the V1 / pre-Epic-C deploy path) is still
///   surfaced.
///
/// See https://github.com/WXYC/wxyc-ios-64/issues/270 for the rationale and
/// `WXYC/Backend-Service#891` for the 5-state wire enum.
public enum PlaycutInlineMetadata {

    /// Returns a composed ``PlaycutMetadata`` when the row's status indicates
    /// enrichment has completed (in any of the three terminal forms), or
    /// `nil` when the consumer should fall back to the proxy fetch.
    public static func from(_ playcut: Playcut) -> PlaycutMetadata? {
        guard let status = playcut.metadataStatus else {
            return nil
        }
        switch status {
        case .pending, .enriching:
            return nil
        case .enrichedMatch, .enrichedNoMatch, .failedNoRetry:
            return PlaycutMetadata(
                artist: ArtistMetadata(
                    bio: playcut.artistBio,
                    wikipediaURL: playcut.artistWikipediaURL
                ),
                album: AlbumMetadata(
                    label: playcut.labelName,
                    releaseYear: playcut.releaseYear,
                    discogsURL: playcut.discogsURL,
                    artworkURL: playcut.artworkURL
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
    }
}
