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
    /// back to a placeholder — see ``isDiscogsUnavailable`` and
    /// `PlaycutDetailView.loadArtworkIfNeeded()`'s artwork-fetch gate. Populated
    /// from either the inline V2 flowsheet row (`Playcut.discogsUnavailable`) or
    /// the `/proxy/metadata/album` decode path
    /// (`WXYCAPIModels.AlbumMetadataResponse.discogsUnavailable`, combined in
    /// `PlaycutMetadataService.fetchMetadata(for:inline:)` via
    /// ``coalescing(over:)``, proxy preferred — #731). Backend emits the field on
    /// the proxy path today; the V2 flowsheet embed does not carry it — the
    /// contract has never declared it on `FlowsheetV2TrackEntry`, and
    /// Backend-side embed emission remains pending (WXYC/Backend-Service#1908) —
    /// so in production the proxy decode is what populates this.
    public let discogsUnavailable: Bool?

    /// Optional free-text reason for ``discogsUnavailable``, surfaced as
    /// secondary text alongside the placeholder when present.
    public let discogsUnavailableNote: String?

    /// Backend-Service's `label` table id for the catalog record label
    /// (`WXYCAPIModels.AlbumMetadataResponse.labelId`, off the linked
    /// flowsheet row's `flowsheet.label_id`). Decode-only (#813): nothing
    /// renders it yet. It would let a future consumer join to the catalog
    /// label record instead of string-matching a name — the plausible
    /// near-term one is a Spotlight `LabelEntity` (#432) — but that consumer
    /// doesn't exist today, so this field carries no UI behavior.
    public let labelId: Int?

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
        discogsUnavailableNote: String? = nil,
        labelId: Int? = nil
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
        self.labelId = labelId
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
    /// Every enrichment-sourced field counts, not just the headline three: a
    /// genre-only answer is a real (if thin) result, and treating it as sparse
    /// would re-fetch it every ``PlaycutMetadataService/sparseAlbumLifespan``
    /// forever. `label` is the one deliberate exclusion — it's a base flowsheet
    /// column, so an album carrying nothing but a label is exactly the
    /// pre-enrichment snapshot rather than a partial success.
    ///
    /// `labelId` is excluded for the same reason as `label`: it's the id
    /// half of the same base flowsheet column (`flowsheet.label_id`), never
    /// a Discogs/LML read, so its presence says nothing about whether
    /// enrichment ran.
    ///
    /// The two ``discogsUnavailable`` fields are tested by *value*, not by
    /// presence, because presence carries no information here.
    /// `library.discogs_unavailable` is `NOT NULL DEFAULT false` and Backend
    /// assigns it to every response whose row resolved to a catalog album, so
    /// `false` rides along on the pre-enrichment answer this predicate exists to
    /// catch; keying on `!= nil` would classify every library-linked play as
    /// non-sparse and make the whole gate inert. `true`, or a note, is the
    /// opposite: an MD sat down and recorded that this release will never carry
    /// Discogs enrichment, which is durable content and belongs on the long TTL.
    ///
    /// Gates the short cache TTL in
    /// `PlaycutMetadataService.fetchAlbumAndStreaming` (#812), mirroring what
    /// ``PlaycutMetadataService/emptyStreamingLifespan`` does on the streaming
    /// side (#303).
    public var isSparse: Bool {
        releaseYear == nil
            && discogsURL == nil
            && discogsArtistId == nil
            && artworkURL == nil
            && fullReleaseDate == nil
            && !isDiscogsUnavailable
            && discogsUnavailableNote == nil
            && (genres ?? []).isEmpty
            && (styles ?? []).isEmpty
            && (criticReviews ?? []).isEmpty
    }

    /// Field-by-field coalesce: this record's populated fields win, `fallback`
    /// fills every gap. Neither side can remove information the other has.
    ///
    /// One definition serves both callers that need to combine two partial
    /// views of the same album: `PlaycutMetadataService`'s V2 fallthrough
    /// (proxy preferred over the inline flowsheet row) and the detail card's
    /// enrichment repair (the finished row preferred over whatever the proxy
    /// resolved first — #812).
    ///
    /// Absence is `nil`, not emptiness: an explicitly empty `genres` array on
    /// the preferred side still wins over a populated fallback. No serving
    /// path distinguishes the two today — the flowsheet decoder and the proxy
    /// decoder both produce `nil` for an absent list.
    public func coalescing(over fallback: AlbumMetadata) -> AlbumMetadata {
        AlbumMetadata(
            label: label ?? fallback.label,
            releaseYear: releaseYear ?? fallback.releaseYear,
            discogsURL: discogsURL ?? fallback.discogsURL,
            discogsArtistId: discogsArtistId ?? fallback.discogsArtistId,
            genres: genres ?? fallback.genres,
            styles: styles ?? fallback.styles,
            fullReleaseDate: fullReleaseDate ?? fallback.fullReleaseDate,
            artworkURL: artworkURL ?? fallback.artworkURL,
            criticReviews: criticReviews ?? fallback.criticReviews,
            discogsUnavailable: discogsUnavailable ?? fallback.discogsUnavailable,
            discogsUnavailableNote: discogsUnavailableNote ?? fallback.discogsUnavailableNote,
            labelId: labelId ?? fallback.labelId
        )
    }
}

public extension ArtistMetadata {
    /// Field-by-field coalesce; see ``AlbumMetadata/coalescing(over:)``.
    func coalescing(over fallback: ArtistMetadata) -> ArtistMetadata {
        ArtistMetadata(
            bio: bio ?? fallback.bio,
            bioTokens: bioTokens ?? fallback.bioTokens,
            wikipediaURL: wikipediaURL ?? fallback.wikipediaURL,
            discogsArtistId: discogsArtistId ?? fallback.discogsArtistId
        )
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

    /// Field-by-field coalesce; see ``AlbumMetadata/coalescing(over:)``.
    public func coalescing(over fallback: StreamingLinks) -> StreamingLinks {
        StreamingLinks(
            spotifyURL: spotifyURL ?? fallback.spotifyURL,
            appleMusicURL: appleMusicURL ?? fallback.appleMusicURL,
            youtubeMusicURL: youtubeMusicURL ?? fallback.youtubeMusicURL,
            bandcampURL: bandcampURL ?? fallback.bandcampURL,
            soundcloudURL: soundcloudURL ?? fallback.soundcloudURL
        )
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

    /// Field-by-field coalesce across all three sub-records; see
    /// ``AlbumMetadata/coalescing(over:)``.
    public func coalescing(over fallback: PlaycutMetadata) -> PlaycutMetadata {
        PlaycutMetadata(
            artist: artist.coalescing(over: fallback.artist),
            album: album.coalescing(over: fallback.album),
            streaming: streaming.coalescing(over: fallback.streaming)
        )
    }
}
