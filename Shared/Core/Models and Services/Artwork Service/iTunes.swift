import UIKit

final class iTunesArtworkFetcher: ArtworkFetcher {
    private let session: WebSession
    private let decoder = JSONDecoder()
    
    init(session: WebSession = URLSession.shared) {
        self.session = session
    }
    
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let searchURL = makeSearchURL(for: playcut)
        let searchData = try await session.data(from: searchURL)
        let results = try decoder.decode(iTunes.SearchResults.self, from: searchData)
        
        guard let result = results.results.first else {
            throw ServiceErrors.noResults
        }
        
        let imageData = try await session.data(from: result.artworkUrl100)
        let image = UIImage(data: imageData)
        
        guard let image = image else {
            throw ServiceErrors.noResults
        }
        
        return image
    }
    
    private func makeSearchURL(for playcut: Playcut) -> URL {
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
}

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
