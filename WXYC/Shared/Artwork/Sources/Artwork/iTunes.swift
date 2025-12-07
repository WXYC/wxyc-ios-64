import Foundation

final class iTunesArtworkService: ArtworkService {
    private let session: WebSession
    private let decoder = JSONDecoder()
    
    init(session: WebSession = URLSession.shared) {
        self.session = session
    }
    
    func fetchArtwork(for playcut: Playcut) async throws -> Image {
        let searchURL = makeSearchURL(for: playcut)
        let searchData = try await session.data(from: searchURL)
        let results = try decoder.decode(iTunes.SearchResults.self, from: searchData)
        
        guard let result = results.results.first else {
            throw ServiceError.noResults
        }
        
        let imageData = try await session.data(from: result.artworkUrl100)
        let image = Image(data: imageData)
        
        guard let image = image else {
            throw ServiceError.noResults
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
            let artworkUrl100: URL
        }
    }
}
