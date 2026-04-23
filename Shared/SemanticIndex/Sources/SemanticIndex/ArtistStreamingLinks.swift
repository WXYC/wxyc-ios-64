//
//  ArtistStreamingLinks.swift
//  SemanticIndex
//
//  Constructs streaming service URLs from semantic-index artist detail
//  and preview data. Used by ArtistStreamingLinksSection in the UI.
//
//  Created by Jake Bromberg on 04/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Streaming service URLs for an artist, constructed from semantic-index data.
///
/// Prefers the Apple Music album link from the preview endpoint when available,
/// falling back to the artist page. Spotify and Bandcamp always link to the
/// artist page.
public struct ArtistStreamingLinks: Sendable {
    /// Apple Music URL — album page (from preview) or artist page (from detail).
    public let appleMusicURL: URL?

    /// Spotify artist page URL.
    public let spotifyURL: URL?

    /// Bandcamp artist page URL.
    public let bandcampURL: URL?

    /// Creates streaming links from artist detail and optional preview data.
    ///
    /// - Parameters:
    ///   - detail: The artist detail containing streaming service IDs.
    ///   - preview: Optional preview data containing Apple Music album link.
    public init(detail: SemanticIndexArtistDetail, preview: SemanticIndexPreview? = nil) {
        self.appleMusicURL = preview?.albumURL
            ?? detail.appleMusicArtistId.flatMap {
                URL(string: "https://music.apple.com/artist/\($0)")
            }

        self.spotifyURL = detail.spotifyArtistId.flatMap {
            URL(string: "https://open.spotify.com/artist/\($0)")
        }

        self.bandcampURL = detail.bandcampId.flatMap {
            URL(string: "https://\($0).bandcamp.com")
        }
    }

    /// Whether any streaming links are available.
    public var hasLinks: Bool {
        appleMusicURL != nil || spotifyURL != nil || bandcampURL != nil
    }
}
