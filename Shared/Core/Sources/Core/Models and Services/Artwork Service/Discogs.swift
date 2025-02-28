import UIKit

final class DiscogsArtworkFetcher: ArtworkFetcher {
    private static let key    = "tYvsaskeJxOQbWoZSSkh"
    private static let secret = "vZuPZFFDerXIPrBfSNnNyDhXjpIUiyXi"
    
    private let session: WebSession
    private let decoder = JSONDecoder()
    
    init(session: WebSession = URLSession.shared) {
        self.session = session
    }
    
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let searchURL = makeSearchURL(for: playcut)
        let searchData = try await session.data(from: searchURL)
        let searchResponse = try decoder.decode(Discogs.SearchResults.self, from: searchData)
        let imageURLs: [URL] = searchResponse.results.map(\.coverImage)
        
        guard let url = imageURLs.first(where: { !$0.lastPathComponent.hasPrefix("spacer.gif") }) else {
            throw ServiceErrors.noResults
        }
        
        let imageData = try await session.data(from: url)
        let image = UIImage(data: imageData)
        
        guard let image = image else {
            throw ServiceErrors.noResults
        }
        
        return image
    }
    
    private func makeSearchURL(for playcut: Playcut) -> URL {
        var components = URLComponents(string: "https://api.discogs.com")!
        components.path = "/database/search"
        components.queryItems = [
            URLQueryItem(name: "artist",  value: playcut.artistName),
            URLQueryItem(name: "album",   value: playcut.releaseTitle),
            URLQueryItem(name: "key", value: Self.key),
            URLQueryItem(name: "secret", value: Self.secret),
        ]
        
        return components.url!
    }
}

private struct Discogs {
    struct SearchResults: Codable {
        let results: [Results]
        
        struct Results: Codable {
            let coverImage: URL
            let masterId: Int
            
            enum CodingKeys: String, CodingKey {
                case coverImage = "cover_image"
                case masterId = "master_id"
            }
        }
    }
}
