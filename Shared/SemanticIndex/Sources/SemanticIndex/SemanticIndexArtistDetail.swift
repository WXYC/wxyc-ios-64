//
//  SemanticIndexArtistDetail.swift
//  SemanticIndex
//
//  Full artist detail from the semantic-index artist endpoint. Extends
//  the basic summary with streaming service IDs and Discogs artist ID.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Full artist detail returned by the semantic-index artist detail endpoint.
///
/// Includes streaming service identifiers (Spotify, Apple Music, Bandcamp)
/// and the Discogs artist ID for fetching artist bio via the existing
/// metadata proxy.
public struct SemanticIndexArtistDetail: Codable, Sendable, Hashable {
    public let id: Int
    public let canonicalName: String
    public let genre: String?
    public let totalPlays: Int?
    public let spotifyArtistId: String?
    public let appleMusicArtistId: String?
    public let bandcampId: String?
    public let discogsArtistId: Int?

    public init(
        id: Int,
        canonicalName: String,
        genre: String? = nil,
        totalPlays: Int? = nil,
        spotifyArtistId: String? = nil,
        appleMusicArtistId: String? = nil,
        bandcampId: String? = nil,
        discogsArtistId: Int? = nil
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.genre = genre
        self.totalPlays = totalPlays
        self.spotifyArtistId = spotifyArtistId
        self.appleMusicArtistId = appleMusicArtistId
        self.bandcampId = bandcampId
        self.discogsArtistId = discogsArtistId
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case canonicalName = "canonical_name"
        case genre
        case totalPlays = "total_plays"
        case spotifyArtistId = "spotify_artist_id"
        case appleMusicArtistId = "apple_music_artist_id"
        case bandcampId = "bandcamp_id"
        case discogsArtistId = "discogs_artist_id"
    }
}
