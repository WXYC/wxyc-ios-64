//
//  SoundCloudService.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

final class SoundCloudService: MusicService {
    let identifier: MusicServiceIdentifier = .soundcloud
    
    init() {}
    
    func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("soundcloud.com")
    }
    
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
    
    func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        // Artwork is fetched as part of fetchMetadata, return cached value
        return track.artworkURL
    }
    
    func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack {
        // Use SoundCloud oEmbed API (no auth required)
        // API: https://soundcloud.com/oembed?format=json&url=[url]
        let encodedUrl = track.url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let apiURL = URL(string: "https://soundcloud.com/oembed?format=json&url=\(encodedUrl)") else {
            return track
        }
        
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return track
        }
        
        // Extract metadata from oEmbed response
        let title = json["title"] as? String
        let artist = json["author_name"] as? String
        
        // Get artwork URL
        var artworkURL: URL?
        if let thumbnailUrlString = json["thumbnail_url"] as? String {
            artworkURL = URL(string: thumbnailUrlString)
        }
        
        return MusicTrack(
            service: track.service,
            url: track.url,
            title: title ?? track.title,
            artist: artist ?? track.artist,
            album: nil, // SoundCloud doesn't have albums
            identifier: track.identifier,
            artworkURL: artworkURL ?? track.artworkURL
        )
    }
}
