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

    // music.youtube.com and youtu.be are handled by the protocol's host-list default below.
    // Plain youtube.com can't join that list: youtube.com hosts far more than music videos, so
    // a bare suffix match would over-match every non-music YouTube link. Only its "/watch" path
    // is a video/track link, which needs its own path-conditional check — hence the override.
    static let hosts = ["music.youtube.com", "youtu.be"]

    init() {}

    func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        if Self.hosts.contains(where: { host.contains($0) }) {
            return true
        }
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
        
        // Use YouTube oEmbed API (no auth required)
        // API: https://www.youtube.com/oembed?url={url}&format=json
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: track.url.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let apiURL = components.url else {
            return track
        }
        
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return track
        }
        
        // Extract metadata from oEmbed response
        let title = json["title"] as? String
        let artist = json["author_name"] as? String
        
        // Use direct YouTube thumbnail URL for better quality than oEmbed thumbnail
        let artworkURL = try await fetchHighQualityThumbnail(videoId: videoId)
        
        // album: nil — YouTube doesn't have albums, and every YouTube track already starts
        // with a nil album from parse(url:), so this leaves it unchanged either way.
        return track.merging(title: title, artist: artist, album: nil, artworkURL: artworkURL)
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
