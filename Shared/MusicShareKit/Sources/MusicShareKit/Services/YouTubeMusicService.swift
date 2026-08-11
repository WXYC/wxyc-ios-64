//
//  YouTubeMusicService.swift
//  MusicShareKit
//
//  YouTube Music URL parsing and track metadata extraction.
//
//  Created by Jake Bromberg on 11/24/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Core
import Foundation

final class YouTubeMusicService: MusicServiceProvider {
    let identifier: MusicService = .youtubeMusic

    // music.youtube.com and youtu.be are handled by the protocol's host-list default.
    // Plain youtube.com can't join that list: youtube.com hosts far more than music videos, so
    // an unconditional host match would claim every non-music YouTube link. Only its "/watch"
    // path is a video/track link, which needs its own path condition — hence the override below.
    static let hosts = ["music.youtube.com", "youtu.be"]

    init() {}

    /// The declarative host/scheme match, *plus* youtube.com's "/watch"-only rule. Delegating the
    /// first half to `matchesDeclaredHostOrScheme` rather than re-implementing it keeps this in
    /// step with the protocol default (a copy would, for one, ignore `schemes` outright).
    func canHandle(url: URL) -> Bool {
        if matchesDeclaredHostOrScheme(url: url) {
            return true
        }

        let host = url.host?.lowercased() ?? ""
        return host.contains("youtube.com") && url.path.contains("/watch")
    }

    func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        var videoId: String?
        
        // Handle youtu.be short URLs
        // Format: https://youtu.be/VIDEO_ID
        if url.host?.lowercased() == "youtu.be" {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if !path.isEmpty {
                videoId = path
            }
        } else {
            // Handle youtube.com and music.youtube.com URLs
            // Format: https://music.youtube.com/watch?v=VIDEO_ID
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                if let vParam = components.queryItems?.first(where: { $0.name == "v" })?.value {
                    videoId = vParam
                }
            }
        }
        
        guard let id = videoId else { return nil }
        
        return MusicTrack(
            service: .youtubeMusic,
            url: url,
            title: nil,
            artist: nil,
            album: nil,
            identifier: id
        )
    }
    
    func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack {
        guard let videoId = track.identifier else { return track }

        // Use YouTube's oEmbed API (no auth required) for title/artist.
        let response = try await OEmbedClient.fetch(endpoint: "https://www.youtube.com/oembed", trackURL: track.url)

        // Use the direct YouTube thumbnail URL for better quality than oEmbed's own thumbnail
        // (oEmbed's response.thumbnailURL is intentionally not used here).
        let artworkURL = try await fetchHighQualityThumbnail(videoId: videoId)

        // album: nil — YouTube doesn't have albums, and every YouTube track already starts
        // with a nil album from parse(url:), so this leaves it unchanged either way.
        return track.merging(title: response.title, artist: response.authorName, album: nil, artworkURL: artworkURL)
    }
    
    private func fetchHighQualityThumbnail(videoId: String) async throws -> URL? {
        // YouTube has a predictable thumbnail URL pattern
        // Try high-res first, fall back to HQ if not available
        let highResUrl = URL(string: "https://img.youtube.com/vi/\(videoId)/maxresdefault.jpg")!
        
        // Check if high-res exists by making a HEAD request
        var request = URLRequest(url: highResUrl)
        request.httpMethod = "HEAD"
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
            return highResUrl
        }
        
        // Fall back to HQ default
        return URL(string: "https://img.youtube.com/vi/\(videoId)/hqdefault.jpg")
    }
}
