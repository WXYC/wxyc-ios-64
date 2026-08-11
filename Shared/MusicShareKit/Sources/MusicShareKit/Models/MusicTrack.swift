//
//  MusicTrack.swift
//  MusicShareKit
//
//  Data model for a track shared from a music service.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import Foundation

public struct MusicTrack: Sendable {
    public let service: MusicService
    public let url: URL
    public let title: String?
    public let artist: String?
    public let album: String?
    public let identifier: String?
    public var artworkURL: URL?

    public init(
        service: MusicService,
        url: URL,
        title: String?,
        artist: String?,
        album: String?,
        identifier: String?,
        artworkURL: URL? = nil
    ) {
        self.service = service
        self.url = url
        self.title = title
        self.artist = artist
        self.album = album
        self.identifier = identifier
        self.artworkURL = artworkURL
    }
    
    /// Display format: "Track Title - Artist (Album)"
    public var displayTitle: String {
        var components: [String] = []
        
        if let title = title {
            components.append(title)
        }
        
        if let artist = artist {
            if components.isEmpty {
                components.append(artist)
            } else {
                components.append("- \(artist)")
            }
        }
        
        if let album = album {
            components.append("(\(album))")
        }
        
        if components.isEmpty {
            return url.absoluteString
        }
        
        return components.joined(separator: " ")
    }

    /// Returns a copy of this track with the given non-nil metadata values applied; any
    /// argument left `nil` keeps the track's existing value for that field. `service`, `url`,
    /// and `identifier` never change — fetching metadata refines a track, it doesn't re-identify
    /// it. This replaces the repeated `MusicTrack(service:url:title:artist:album:identifier:
    /// artworkURL:)` rebuild that ended every `MusicServiceProvider.fetchMetadata(for:)`.
    public func merging(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        artworkURL: URL? = nil
    ) -> MusicTrack {
        MusicTrack(
            service: service,
            url: url,
            title: title ?? self.title,
            artist: artist ?? self.artist,
            album: album ?? self.album,
            identifier: identifier,
            artworkURL: artworkURL ?? self.artworkURL
        )
    }
}
