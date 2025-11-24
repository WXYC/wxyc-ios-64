//
//  SoundCloudService.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

public final class SoundCloudService: MusicService {
    public let identifier: MusicServiceIdentifier = .soundcloud
    
    public init() {}
    
    public func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("soundcloud.com")
    }
    
    public func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        // SoundCloud URLs format:
        // https://soundcloud.com/[artist]/[track-name]
        // https://soundcloud.com/[artist]/[track-name]/[optional-slug]
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        var title: String?
        var artist: String?
        var identifier: String?
        
        if pathComponents.count >= 2 {
            artist = pathComponents[0].replacingOccurrences(of: "-", with: " ").capitalized
            title = pathComponents[1].replacingOccurrences(of: "-", with: " ").capitalized
            
            // Use the full path as identifier
            identifier = pathComponents.joined(separator: "/")
        }
        
        return MusicTrack(
            service: .soundcloud,
            url: url,
            title: title,
            artist: artist,
            album: nil,
            identifier: identifier
        )
    }
    
    public func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        // Use SoundCloud oEmbed API (no auth required)
        // API: https://soundcloud.com/oembed?format=json&url=[url]
        let encodedUrl = track.url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let apiURL = URL(string: "https://soundcloud.com/oembed?format=json&url=\(encodedUrl)") else {
            return nil
        }
        
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let thumbnailUrlString = json?["thumbnail_url"] as? String else {
            return nil
        }
        
        return URL(string: thumbnailUrlString)
    }
}

