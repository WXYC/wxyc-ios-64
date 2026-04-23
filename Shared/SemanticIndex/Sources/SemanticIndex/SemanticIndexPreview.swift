//
//  SemanticIndexPreview.swift
//  SemanticIndex
//
//  Preview data from the semantic-index preview endpoint, providing
//  iTunes artwork, track names, and Apple Music album links.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Preview data from the semantic-index artist preview endpoint.
///
/// Provides artwork URLs, track names, and Apple Music album deep links
/// sourced from the iTunes Search API cache in the Transition Player backend.
public struct SemanticIndexPreview: Codable, Sendable, Hashable {
    public let previewURL: URL?
    public let trackName: String?
    public let artistName: String?
    public let artworkURL: URL?
    public let albumName: String?
    public let albumURL: URL?

    public init(
        previewURL: URL? = nil,
        trackName: String? = nil,
        artistName: String? = nil,
        artworkURL: URL? = nil,
        albumName: String? = nil,
        albumURL: URL? = nil
    ) {
        self.previewURL = previewURL
        self.trackName = trackName
        self.artistName = artistName
        self.artworkURL = artworkURL
        self.albumName = albumName
        self.albumURL = albumURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.trackName = try container.decodeIfPresent(String.self, forKey: .trackName)
        self.artistName = try container.decodeIfPresent(String.self, forKey: .artistName)
        self.albumName = try container.decodeIfPresent(String.self, forKey: .albumName)
        self.previewURL = try container.decodeIfPresent(String.self, forKey: .previewURL).flatMap { URL(string: $0) }
        self.artworkURL = try container.decodeIfPresent(String.self, forKey: .artworkURL).flatMap { URL(string: $0) }
        self.albumURL = try container.decodeIfPresent(String.self, forKey: .albumURL).flatMap { URL(string: $0) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(trackName, forKey: .trackName)
        try container.encodeIfPresent(artistName, forKey: .artistName)
        try container.encodeIfPresent(albumName, forKey: .albumName)
        try container.encodeIfPresent(previewURL?.absoluteString, forKey: .previewURL)
        try container.encodeIfPresent(artworkURL?.absoluteString, forKey: .artworkURL)
        try container.encodeIfPresent(albumURL?.absoluteString, forKey: .albumURL)
    }

    private enum CodingKeys: String, CodingKey {
        case previewURL = "preview_url"
        case trackName = "track_name"
        case artistName = "artist_name"
        case artworkURL = "artwork_url"
        case albumName = "album_name"
        case albumURL = "album_url"
    }
}
