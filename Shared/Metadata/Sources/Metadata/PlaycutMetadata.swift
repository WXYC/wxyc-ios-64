//
//  PlaycutMetadata.swift
//  Metadata
//
//  Extended metadata for a playcut (artist bio, release info, etc.).
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Playlist

// MARK: - Artist Metadata

/// Metadata specific to an artist, cached by Discogs artist ID.
public struct ArtistMetadata: Sendable, Equatable, Codable {
    /// Artist biography from Discogs
    public let bio: String?

    /// Pre-parsed bio tokens from the server's Discogs markup parser.
    /// When available, these can be rendered directly without client-side parsing.
    public let bioTokens: [ResolvedBioToken]?

    /// Link to artist's Wikipedia page
    public let wikipediaURL: URL?

    /// Discogs artist ID for cache key lookups
    public let discogsArtistId: Int?

    public init(
        bio: String? = nil,
        bioTokens: [ResolvedBioToken]? = nil,
        wikipediaURL: URL? = nil,
        discogsArtistId: Int? = nil
    ) {
        self.bio = bio
        self.bioTokens = bioTokens
        self.wikipediaURL = wikipediaURL
        self.discogsArtistId = discogsArtistId
    }

    public static let empty = ArtistMetadata()
}

// MARK: - Critic Review
//
// `CriticReview` itself lives in `Playlist` (`CriticReview.swift`), not here —
// hoisted out for #695 so `Playcut.criticReviews` (Playlist) and
// `AlbumMetadata.criticReviews` (below) share exactly one type. `Playlist`
// doesn't depend on `Metadata`, so the type had to move down to the package
// both sides can see; this file re-exposes it simply by importing `Playlist`
// above. See that file's doc comment for the full rationale.

// MARK: - Album Metadata

/// Metadata specific to an album/release, cached by artist+release key.
public struct AlbumMetadata: Sendable, Equatable, Codable {
    /// Record label name
    public let label: String?

    /// Release year
    public let releaseYear: Int?

    /// Link to the release on Discogs
    public let discogsURL: URL?

    /// Discogs artist ID (links to artist metadata for efficient lookups)
    public let discogsArtistId: Int?

    /// Discogs genre classifications
    public let genres: [String]?

    /// Discogs style classifications (more specific than genres)
    public let styles: [String]?

    /// Full release date when available (e.g. "2024-03-15")
    public let fullReleaseDate: String?

    /// Artwork image URL from the metadata proxy (Discogs cover image)
    public let artworkURL: URL?

    /// Attributed external critic-review snippets for this album (ADR 0012).
    /// `nil` when the serve path didn't attach any (flag off, or no rows); the
    /// Reviews section gates on `hasCriticReviews` and never folds into
    /// `hasMetadataSectionContent`.
    public let criticReviews: [CriticReview]?

    /// MD-set marker indicating this release is intentionally not on Discogs
    /// (the "Not on Discogs" flag epic, Backend-Service#1280). When `true`,
    /// artwork rendering suppresses the Discogs-derived artwork/URL and falls
    /// back to a placeholder — see `isDiscogsUnavailable` and
    /// `PlaycutDetailView.apply(_:)`'s artwork-fetch gate. Populated from either the inline
    /// V2 flowsheet row (`Playcut.discogsUnavailable`) or the
    /// `/proxy/metadata/album` decode path (`WXYCAPIModels.AlbumMetadataResponse
    /// .discogsUnavailable`, wired in `PlaycutMetadataService.mergeAlbum`,
    /// proxy preferred — #731). Backend emits the field on both paths,
    /// including the flowsheet embed (`FlowsheetV2TrackEntry.discogsUnavailable`,
    /// WXYC/Backend-Service#1908), so either source can populate it.
    public let discogsUnavailable: Bool?

    /// Optional free-text reason for ``discogsUnavailable``, surfaced as
    /// secondary text alongside the placeholder when present.
    public let discogsUnavailableNote: String?

    public init(
        label: String? = nil,
        releaseYear: Int? = nil,
        discogsURL: URL? = nil,
        discogsArtistId: Int? = nil,
        genres: [String]? = nil,
        styles: [String]? = nil,
        fullReleaseDate: String? = nil,
        artworkURL: URL? = nil,
        criticReviews: [CriticReview]? = nil,
        discogsUnavailable: Bool? = nil,
        discogsUnavailableNote: String? = nil
    ) {
        self.label = label
        self.releaseYear = releaseYear
        self.discogsURL = discogsURL
        self.discogsArtistId = discogsArtistId
        self.genres = genres
        self.styles = styles
        self.fullReleaseDate = fullReleaseDate
        self.artworkURL = artworkURL
        self.criticReviews = criticReviews
        self.discogsUnavailable = discogsUnavailable
        self.discogsUnavailableNote = discogsUnavailableNote
    }

    public static let empty = AlbumMetadata()

    /// Whether the album has at least one critic review worth rendering.
    /// Gates `ReviewsSection` in the detail view — mirrors
    /// `StreamingLinks.hasAny`, deliberately separate from
    /// `hasMetadataSectionContent`.
    public var hasCriticReviews: Bool {
        !(criticReviews ?? []).isEmpty
    }

    /// Whether Discogs-derived artwork should be suppressed in favor of the
    /// "Not on Discogs" placeholder. `false` (not just `nil`-coalesced) reads
    /// more clearly than `discogsUnavailable == true` at every call site.
    public var isDiscogsUnavailable: Bool {
        discogsUnavailable == true
    }

    /// Whether this record carries no enrichment output at all — the shape the
    /// metadata proxy returns for a row Backend hasn't finished enriching, and
    /// the shape `PlaycutMetadataService`'s throw-path fallback synthesizes
    /// (`AlbumMetadata(label: playcut.labelName)`).
    ///
    /// Keyed on the three fields that only ever come from enrichment. `label`
    /// is deliberately excluded: it's a base flowsheet column, so an album
    /// carrying nothing but a label is exactly the pre-enrichment snapshot, not
    /// a partial success. Gates the short cache TTL in
    /// `PlaycutMetadataService.fetchAlbumAndStreaming` (#812), mirroring what
    /// ``PlaycutMetadataService/emptyStreamingLifespan`` does on the streaming
    /// side (#303).
    public var isSparse: Bool {
        releaseYear == nil && discogsURL == nil && artworkURL == nil
    }
}

// MARK: - Streaming Links

/// Links to streaming platforms, cached by artist+song key.
public struct StreamingLinks: Sendable, Equatable, Codable {
    /// Link to track on Spotify
    public let spotifyURL: URL?

    /// Link to track on Apple Music
    public let appleMusicURL: URL?

    /// Link to track on YouTube Music
    public let youtubeMusicURL: URL?

    /// Link to track on Bandcamp
    public let bandcampURL: URL?

    /// Link to track on SoundCloud
    public let soundcloudURL: URL?

    public init(
        spotifyURL: URL? = nil,
        appleMusicURL: URL? = nil,
        youtubeMusicURL: URL? = nil,
        bandcampURL: URL? = nil,
        soundcloudURL: URL? = nil
    ) {
        self.spotifyURL = spotifyURL
        self.appleMusicURL = appleMusicURL
        self.youtubeMusicURL = youtubeMusicURL
        self.bandcampURL = bandcampURL
        self.soundcloudURL = soundcloudURL
    }

    public static let empty = StreamingLinks()

    /// Check if any streaming links are available
    public var hasAny: Bool {
        spotifyURL != nil ||
        appleMusicURL != nil ||
        youtubeMusicURL != nil ||
        bandcampURL != nil ||
        soundcloudURL != nil
    }
}

// MARK: - Playcut Metadata (Composite)

/// Extended metadata for a Playcut, composed from artist, album, and streaming metadata.
public struct PlaycutMetadata: Sendable, Equatable, Codable {
    /// Artist-level metadata (bio, Wikipedia)
    public let artist: ArtistMetadata

    /// Album-level metadata (label, year, Discogs URL)
    public let album: AlbumMetadata

    /// Streaming platform links
    public let streaming: StreamingLinks

    public init(
        artist: ArtistMetadata = .empty,
        album: AlbumMetadata = .empty,
        streaming: StreamingLinks = .empty
    ) {
        self.artist = artist
        self.album = album
        self.streaming = streaming
    }

    // MARK: - Backward Compatibility

    /// Legacy initializer for backward compatibility
    public init(
        label: String? = nil,
        releaseYear: Int? = nil,
        discogsURL: URL? = nil,
        artistBio: String? = nil,
        wikipediaURL: URL? = nil,
        spotifyURL: URL? = nil,
        appleMusicURL: URL? = nil,
        youtubeMusicURL: URL? = nil,
        bandcampURL: URL? = nil,
        soundcloudURL: URL? = nil,
        discogsArtistId: Int? = nil
    ) {
        self.artist = ArtistMetadata(
            bio: artistBio,
            wikipediaURL: wikipediaURL,
            discogsArtistId: discogsArtistId
        )
        self.album = AlbumMetadata(
            label: label,
            releaseYear: releaseYear,
            discogsURL: discogsURL,
            discogsArtistId: discogsArtistId
        )
        self.streaming = StreamingLinks(
            spotifyURL: spotifyURL,
            appleMusicURL: appleMusicURL,
            youtubeMusicURL: youtubeMusicURL,
            bandcampURL: bandcampURL,
            soundcloudURL: soundcloudURL
        )
    }

    /// Empty metadata instance
    public static let empty = PlaycutMetadata()

    // MARK: - Backward Compatible Accessors

    /// Record label name
    public var label: String? { album.label }

    /// Release year
    public var releaseYear: Int? { album.releaseYear }

    /// Link to the release on Discogs
    public var discogsURL: URL? { album.discogsURL }

    /// Artist biography from Discogs
    public var artistBio: String? { artist.bio }

    /// Link to artist's Wikipedia page
    public var wikipediaURL: URL? { artist.wikipediaURL }

    /// Link to track on Spotify
    public var spotifyURL: URL? { streaming.spotifyURL }

    /// Link to track on Apple Music
    public var appleMusicURL: URL? { streaming.appleMusicURL }

    /// Link to track on YouTube Music
    public var youtubeMusicURL: URL? { streaming.youtubeMusicURL }

    /// Link to track on Bandcamp
    public var bandcampURL: URL? { streaming.bandcampURL }

    /// Link to track on SoundCloud
    public var soundcloudURL: URL? { streaming.soundcloudURL }

    /// Check if any streaming links are available
    public var hasStreamingLinks: Bool { streaming.hasAny }

    /// Whether the playcut metadata section card (label, year, genre/style tags, artist bio,
    /// the "Not on Discogs" row) has any field worth rendering. Gates `PlaycutMetadataSection`
    /// in the detail view — keep in sync with that view's rendered fields.
    public var hasMetadataSectionContent: Bool {
        label?.isEmpty == false
            || releaseYear != nil
            || album.genres?.isEmpty == false
            || album.styles?.isEmpty == false
            || artistBio?.isEmpty == false
            || album.isDiscogsUnavailable
    }
}
