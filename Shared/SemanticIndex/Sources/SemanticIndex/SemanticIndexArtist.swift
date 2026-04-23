//
//  SemanticIndexArtist.swift
//  SemanticIndex
//
//  Artist summary from the semantic-index search endpoint. Maps to
//  the API's ArtistSummary response model.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// An artist summary returned by the semantic-index search endpoint.
///
/// Contains the artist's graph ID, canonical name, genre classification,
/// and total play count across WXYC's 22-year flowsheet history.
public struct SemanticIndexArtist: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let canonicalName: String
    public let genre: String?
    public let totalPlays: Int?

    public init(id: Int, canonicalName: String, genre: String? = nil, totalPlays: Int? = nil) {
        self.id = id
        self.canonicalName = canonicalName
        self.genre = genre
        self.totalPlays = totalPlays
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case canonicalName = "canonical_name"
        case genre
        case totalPlays = "total_plays"
    }
}
