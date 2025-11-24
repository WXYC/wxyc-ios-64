//
//  BandcampService.swift
//  MusicShareKit
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation

public class BandcampService: MusicService {
    public let identifier: MusicServiceIdentifier = .bandcamp
    
    public init() {}
    
    public func canHandle(url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host.contains("bandcamp.com")
    }
    
    public func parse(url: URL) -> MusicTrack? {
        guard canHandle(url: url) else { return nil }
        
        // Bandcamp URLs can be:
        // https://[artist].bandcamp.com/track/[track-name]
        // https://[artist].bandcamp.com/album/[album-name]
        // https://[artist].bandcamp.com/track/[track-name]?from=album&album=[album-name]
        
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let hostComponents = url.host?.lowercased().split(separator: ".") ?? []
        
        var title: String?
        var artist: String?
        var album: String?
        var identifier: String?
        
        // Extract artist from subdomain
        if let firstComponent = hostComponents.first {
            artist = String(firstComponent).replacingOccurrences(of: "-", with: " ").capitalized
        }
        
        // Extract track/album info from path
        if pathComponents.count >= 2 {
            let type = pathComponents[0] // "track" or "album"
            let name = pathComponents[1]
            
            // Decode URL-encoded name
            title = name.replacingOccurrences(of: "-", with: " ").capitalized
            identifier = name
            
            if type == "album" {
                album = title
            }
        }
        
        // Check for album info in query parameters
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let albumParam = components.queryItems?.first(where: { $0.name == "album" })?.value {
            album = albumParam.replacingOccurrences(of: "-", with: " ").capitalized
        }
        
        return MusicTrack(
            service: .bandcamp,
            url: url,
            title: title,
            artist: artist,
            album: album,
            identifier: identifier
        )
    }
    
    public func fetchArtwork(for track: MusicTrack) async throws -> URL? {
        // Bandcamp doesn't have a public oEmbed API, so we need to scrape the page
        // Look for og:image meta tag in the HTML
        let (data, _) = try await URLSession.shared.data(from: track.url)
        
        guard let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        // Look for og:image meta tag
        // Pattern: <meta property="og:image" content="https://...">
        let pattern = #"<meta\s+property=\"og:image\"\s+content=\"([^\"]+)\""#
        let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let range = NSRange(html.startIndex..., in: html)
        
        if let match = regex?.firstMatch(in: html, options: [], range: range),
           let urlRange = Range(match.range(at: 1), in: html) {
            let artworkUrlString = String(html[urlRange])
            return URL(string: artworkUrlString)
        }
        
        return nil
    }
}

