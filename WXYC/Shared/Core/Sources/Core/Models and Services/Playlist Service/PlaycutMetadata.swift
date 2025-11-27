//
//  PlaycutMetadata.swift
//  Core
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

/// Extended metadata for a Playcut, fetched from external services
public struct PlaycutMetadata: Sendable, Equatable {
    // MARK: - Discogs Metadata
    
    /// Record label name
    public let label: String?
    
    /// Release year
    public let releaseYear: Int?
    
    /// Link to the release on Discogs
    public let discogsURL: URL?
    
    /// Artist biography from Discogs
    public let artistBio: String?
    
    /// Link to artist's Wikipedia page
    public let wikipediaURL: URL?
    
    // MARK: - Streaming Platform Links
    
    /// Link to track/album on Spotify
    public let spotifyURL: URL?
    
    /// Link to track/album on Apple Music
    public let appleMusicURL: URL?
    
    /// Link to track/album on YouTube Music
    public let youtubeMusicURL: URL?
    
    /// Link to track/album on Bandcamp
    public let bandcampURL: URL?
    
    /// Link to track/album on SoundCloud
    public let soundcloudURL: URL?
    
    // MARK: - Initialization
    
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
        soundcloudURL: URL? = nil
    ) {
        self.label = label
        self.releaseYear = releaseYear
        self.discogsURL = discogsURL
        self.artistBio = artistBio
        self.wikipediaURL = wikipediaURL
        self.spotifyURL = spotifyURL
        self.appleMusicURL = appleMusicURL
        self.youtubeMusicURL = youtubeMusicURL
        self.bandcampURL = bandcampURL
        self.soundcloudURL = soundcloudURL
    }
    
    /// Empty metadata instance
    public static let empty = PlaycutMetadata()
    
    /// Check if any streaming links are available
    public var hasStreamingLinks: Bool {
        spotifyURL != nil ||
        appleMusicURL != nil ||
        youtubeMusicURL != nil ||
        bandcampURL != nil ||
        soundcloudURL != nil
    }
    
    /// Check if any metadata is available
    public var hasAnyData: Bool {
        label != nil ||
        releaseYear != nil ||
        discogsURL != nil ||
        artistBio != nil ||
        wikipediaURL != nil ||
        hasStreamingLinks
    }
}

// MARK: - Builder Pattern for Incremental Updates

extension PlaycutMetadata {
    /// Merge with another metadata instance, preferring non-nil values from the other
    public func merging(with other: PlaycutMetadata) -> PlaycutMetadata {
        PlaycutMetadata(
            label: other.label ?? self.label,
            releaseYear: other.releaseYear ?? self.releaseYear,
            discogsURL: other.discogsURL ?? self.discogsURL,
            artistBio: other.artistBio ?? self.artistBio,
            wikipediaURL: other.wikipediaURL ?? self.wikipediaURL,
            spotifyURL: other.spotifyURL ?? self.spotifyURL,
            appleMusicURL: other.appleMusicURL ?? self.appleMusicURL,
            youtubeMusicURL: other.youtubeMusicURL ?? self.youtubeMusicURL,
            bandcampURL: other.bandcampURL ?? self.bandcampURL,
            soundcloudURL: other.soundcloudURL ?? self.soundcloudURL
        )
    }
}

