//
//  SoundCloudService.swift
//  MusicShareKit
//
//  SoundCloud URL parsing and track metadata extraction.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import Foundation

final class SoundCloudService: MusicServiceProvider {
    let identifier: MusicService = .soundcloud
    static let hosts = ["soundcloud.com"]

    init() {}

    func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        // SoundCloud URLs format:
        // https://soundcloud.com/[artist]/[track-name]
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard pathComponents.count >= 2 else { return nil }
        
        // Use the path as identifier
        let identifier = pathComponents.joined(separator: "/")
        
        return MusicTrack(
            service: .soundcloud,
            url: url,
            title: nil,
            artist: nil,
            album: nil,
            identifier: identifier
        )
    }
    
    func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack {
        // Use SoundCloud's oEmbed API (no auth required)
        let response = try await OEmbedClient.fetch(endpoint: "https://soundcloud.com/oembed", trackURL: track.url)

        // album: nil — SoundCloud doesn't have albums, and every SoundCloud track already
        // starts with a nil album from parse(url:), so this leaves it unchanged either way.
        return track.merging(title: response.title, artist: response.authorName, album: nil, artworkURL: response.thumbnailURL)
    }
}
