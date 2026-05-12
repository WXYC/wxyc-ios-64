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
    public let previewUrl: String?
    public let trackName: String?
    public let artistName: String?
    public let artworkUrl: String?
    public let albumName: String?
    public let albumUrl: String?

    public init(
        previewUrl: String? = nil,
        trackName: String? = nil,
        artistName: String? = nil,
        artworkUrl: String? = nil,
        albumName: String? = nil,
        albumUrl: String? = nil
    ) {
        self.previewUrl = previewUrl
        self.trackName = trackName
        self.artistName = artistName
        self.artworkUrl = artworkUrl
        self.albumName = albumName
        self.albumUrl = albumUrl
    }

    private enum CodingKeys: String, CodingKey {
        case previewUrl = "preview_url"
        case trackName = "track_name"
        case artistName = "artist_name"
        case artworkUrl = "artwork_url"
        case albumName = "album_name"
        case albumUrl = "album_url"
    }

    /// The artwork URL as a typed `URL`, or `nil` if the string is missing or invalid.
    public var artworkURL: URL? {
        artworkUrl.flatMap { URL(string: $0) }
    }

    /// The Apple Music album URL as a typed `URL`, or `nil` if the string is missing or invalid.
    public var albumURL: URL? {
        albumUrl.flatMap { URL(string: $0) }
    }
}
