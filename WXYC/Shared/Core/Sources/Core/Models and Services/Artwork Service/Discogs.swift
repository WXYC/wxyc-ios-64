import UIKit
import Secrets

final class DiscogsArtworkFetcher: ArtworkFetcher {
    private static let key    = Secrets.discogsApiKeyV2_5
    private static let secret = Secrets.discogsApiSecretV2_5
    
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
            throw ServiceError.noResults
        }
        
        let imageData = try await session.data(from: url)
        let image = UIImage(data: imageData)
        
        guard let image = image else {
            throw ServiceError.noResults
        }
        
        return image
    }
    
    private func makeSearchURL(for playcut: Playcut) -> URL {
        var releaseTitle: String? = playcut.releaseTitle
        if let title = playcut.releaseTitle,
           title.lowercased() == "s/t" {
            releaseTitle = playcut.artistName
        }
        
        var components = URLComponents(string: "https://api.discogs.com")!
        components.path = "/database/search"
        components.queryItems = .init([
            "artist" : playcut.artistName,
            "release_title" : releaseTitle,
            "key" : Self.key,
            "secret" : Self.secret,
        ])
        
        return components.url!
    }
}

extension [URLQueryItem] {
    init(_ parameters: [String: String?]) {
        self = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
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
