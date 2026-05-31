//
//  MusicServiceProvider.swift
//  MusicShareKit
//
//  Protocol implemented by per-service URL handlers (Apple Music, Spotify, Bandcamp, etc.).
//  Conformers identify whether they own a URL and parse it into a MusicTrack.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import Foundation

public protocol MusicServiceProvider: Sendable {
    var identifier: MusicService { get }

    /// Check if this service can handle the given URL
    func canHandle(url: URL) -> Bool

    /// Parse the URL and extract metadata to create a MusicTrack
    func parse(url: URL) -> MusicTrack?

    /// Fetch artwork URL for the track (async)
    func fetchArtwork(for track: MusicTrack) async throws -> URL?

    /// Fetch full metadata for the track (async). Returns updated track with title, artist, album, and artwork.
    /// Default implementation returns the original track unchanged.
    func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack
}

extension MusicServiceProvider {
    /// Default implementation returns the track unchanged
    public func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack {
        return track
    }
}
