import Foundation

struct iTunes {
    private init() { }
    
    struct SearchResults: Codable {
        let results: [Item]
        
        struct Item: Codable {
            let artistName: String
            let trackName: String?
            let artworkUrl100: URL
        }
    }
}

final class iTunesConfiguration: RemoteArtworkFetcherConfiguration {
    static func makeSearchURL(for playcut: Playcut) -> URL {
        var components = URLComponents(string: "https://itunes.apple.com")!
        components.path = "/search"
        
        if let album = playcut.releaseTitle {
            components.queryItems = [
                URLQueryItem(name: "term", value: "\(playcut.artistName) \(album)"),
                URLQueryItem(name: "entity", value: "album")
            ]
        } else {
            components.queryItems = [
                URLQueryItem(name: "term", value: "\(playcut.artistName) \(playcut.songTitle)"),
                URLQueryItem(name: "entity", value: "song")
            ]
        }
        
        return components.url!
    }
    
    static func extractURL(from data: Data) throws -> URL {
        let decoder = JSONDecoder()
        let results = try decoder.decode(iTunes.SearchResults.self, from: data)
        
        if let item = results.results.first {
            return item.artworkUrl100
        } else {
            throw ServiceErrors.noResults
        }
    }
}
