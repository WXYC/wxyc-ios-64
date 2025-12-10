//
//  BandcampService.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

final class BandcampService: MusicService {
    let identifier: MusicServiceIdentifier = .bandcamp
    
    init() {}
    
    func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("bandcamp.com")
    }
    
    func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        // Bandcamp URLs:
        // https://[artist].bandcamp.com/track/[track-name]
        // https://[artist].bandcamp.com/album/[album-name]
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        
        guard pathComponents.count >= 2 else { return nil }
        
        let type = pathComponents[0] // "track" or "album"
        let name = pathComponents[1]
        
        return MusicTrack(
            service: .bandcamp,
            url: url,
            title: nil,
            artist: nil,
            album: nil,
            identifier: "\(type):\(name)"
        )
    }
    
    func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        // Artwork is fetched as part of fetchMetadata, return cached value
        return track.artworkURL
    }
    
    func fetchMetadata(for track: MusicTrack) async throws -> MusicTrack {
        // Bandcamp doesn't have a public API, so we scrape the page for Open Graph tags
        let (data, _) = try await URLSession.shared.data(from: track.url)
        
        guard let html = String(data: data, encoding: .utf8) else {
            return track
        }
        
        // Extract og:title - format is typically "Song Title, by Artist" or "Album Title | Artist"
        let ogTitle = extractMetaContent(from: html, property: "og:title")
        
        // Extract og:image for artwork
        let ogImage = extractMetaContent(from: html, property: "og:image")
        let artworkURL = ogImage.flatMap { URL(string: $0) }
        
        // Parse title and artist from og:title
        var title: String?
        var artist: String?
        var album: String?
        
        if let fullTitle = ogTitle {
            // Try "Title, by Artist" format first (tracks)
            if let byRange = fullTitle.range(of: ", by ", options: .caseInsensitive) {
                title = String(fullTitle[..<byRange.lowerBound])
                artist = String(fullTitle[byRange.upperBound...])
            }
            // Try "Title | Artist" format (albums)
            else if let pipeRange = fullTitle.range(of: " | ", options: .backwards) {
                title = String(fullTitle[..<pipeRange.lowerBound])
                artist = String(fullTitle[pipeRange.upperBound...])
            }
            else {
                title = fullTitle
            }
        }
        
        // Fall back to extracting artist from subdomain if not found
        if artist == nil {
            let hostComponents = track.url.host?.lowercased().split(separator: ".") ?? []
            if let firstComponent = hostComponents.first, firstComponent != "www" {
                artist = String(firstComponent).replacingOccurrences(of: "-", with: " ").capitalized
            }
        }
        
        // Check if this is an album URL and set album name
        if let identifier = track.identifier, identifier.hasPrefix("album:") {
            album = title
        }
        
        return MusicTrack(
            service: track.service,
            url: track.url,
            title: nil,
            artist: artist ?? track.artist,
            album: album ?? track.album,
            identifier: track.identifier,
            artworkURL: artworkURL ?? track.artworkURL
        )
    }
    
    private func extractMetaContent(from html: String, property: String) -> String? {
        // Match both property="og:xxx" and name="og:xxx" formats
        // Also handle different attribute orders
        let patterns = [
            #"<meta\s+property="\#(property)"\s+content="([^"]+)""#,
            #"<meta\s+content="([^"]+)"\s+property="\#(property)""#,
            #"<meta\s+name="\#(property)"\s+content="([^"]+)""#,
            #"<meta\s+content="([^"]+)"\s+name="\#(property)""#
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(html.startIndex..., in: html)
                if let match = regex.firstMatch(in: html, options: [], range: range) {
                    // Content is in capture group 1 for property-first, or group 1 for content-first
                    if let contentRange = Range(match.range(at: 1), in: html) {
                        return String(html[contentRange])
                    }
                }
            }
        }
        
        return nil
    }
}
