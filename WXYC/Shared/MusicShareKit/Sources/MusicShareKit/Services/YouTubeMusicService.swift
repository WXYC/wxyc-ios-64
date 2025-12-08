//
//  YouTubeMusicService.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

final class YouTubeMusicService: MusicService {
    let identifier: MusicServiceIdentifier = .youtubeMusic
    
    init() {}
    
    func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("music.youtube.com") || 
               (host.contains("youtube.com") && url.path.contains("/watch")) ||
               host.contains("youtu.be")
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
    
    func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        // Artwork is fetched as part of fetchMetadata, return cached value
        return track.artworkURL
    }
    
    func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack {
        guard let videoId = track.identifier else { return track }
        
        // Use YouTube oEmbed API (no auth required)
        // API: https://www.youtube.com/oembed?url={url}&format=json
        let encodedUrl = track.url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let apiURL = URL(string: "https://www.youtube.com/oembed?url=\(encodedUrl)&format=json") else {
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
        
        return MusicTrack(
            service: track.service,
            url: track.url,
            title: title ?? track.title,
            artist: artist ?? track.artist,
            album: nil, // YouTube doesn't have albums
            identifier: track.identifier,
            artworkURL: artworkURL ?? track.artworkURL
        )
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
