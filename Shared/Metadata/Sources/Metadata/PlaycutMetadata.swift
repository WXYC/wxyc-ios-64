//
//  PlaycutMetadata.swift
//  Core
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

// MARK: - Artist Metadata

/// Metadata specific to an artist, cached by Discogs artist ID.
public struct ArtistMetadata: Sendable, Equatable, Codable {
    /// Artist biography from Discogs
    public let bio: String?
    
    /// Link to artist's Wikipedia page
    public let wikipediaURL: URL?
    
    /// Discogs artist ID for cache key lookups
    public let discogsArtistId: Int?
    
    public init(
        bio: String? = nil,
        wikipediaURL: URL? = nil,
        discogsArtistId: Int? = nil
    ) {
        self.bio = bio
        self.wikipediaURL = wikipediaURL
        self.discogsArtistId = discogsArtistId
    }

    public static let empty = ArtistMetadata()
}

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

    public init(
        label: String? = nil,
        releaseYear: Int? = nil,
        discogsURL: URL? = nil,
        discogsArtistId: Int? = nil
    ) {
        self.label = label
        self.releaseYear = releaseYear
        self.discogsURL = discogsURL
        self.discogsArtistId = discogsArtistId
    }

    public static let empty = AlbumMetadata()
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
}
