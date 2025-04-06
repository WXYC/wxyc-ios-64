import UIKit
import Secrets
import Logger

final class DiscogsArtworkFetcher: ArtworkFetcher {
    private static let key    = Secrets.discogsApiKeyV2_5
    private static let secret = Secrets.discogsApiSecretV2_5
    
    private let session: WebSession
    private let decoder = JSONDecoder()
    
    init(session: WebSession = URLSession.shared) {
        self.session = session
    }
    
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let url: URL
        if let albumArtURL = try await fetchAlbumArtURL(for: playcut) {
            url = albumArtURL
        } else if let artistArtURL = try await fetchArtistArtURL(for: playcut) {
            url = artistArtURL
        } else {
            throw ServiceError.noResults
        }
        
        let imageData = try await session.data(from: url)
        let image = UIImage(data: imageData)
        
        guard let image else {
            throw ServiceError.noResults
        }
        
        return image
    }
    
    private func fetchAlbumArtURL(for playcut: Playcut) async throws -> URL? {
        let searchURL = makeArtworkSearchURL(for: playcut)
        return try await fetchArtURL(for: searchURL)
    }
    
    private func makeArtworkSearchURL(for playcut: Playcut) -> URL {
        var releaseTitle: String? = playcut.releaseTitle
        if let title = playcut.releaseTitle,
           title.lowercased() == "s/t" {
            releaseTitle = playcut.artistName
        }
        
        var searchTerms = [
            playcut.artistName,
        ]
        
        if let releaseTitle {
            searchTerms.append(releaseTitle)
        }
        
        var components = URLComponents(string: "https://api.discogs.com")!
        components.path = "/database/search"
        components.queryItems = .init([
            "q" : searchTerms.joined(separator: " "),
            "key" : Self.key,
            "secret" : Self.secret,
        ])
        
        return components.url!
    }
    
    func fetchArtistArtURL(for playcut: Playcut) async throws -> URL? {
        let searchURL = makeArtistSearchURL(for: playcut)
        return try await fetchArtURL(for: searchURL)
    }
    
    func makeArtistSearchURL(for playcut: Playcut) -> URL {
        var components = URLComponents(string: "https://api.discogs.com")!
        components.path = "/database/search"
        components.queryItems = .init([
            "type" : "artist",
            "title" : playcut.artistName,
            "key" : Self.key,
            "secret" : Self.secret,
        ])
        
        return components.url!
    }
    
    func fetchArtURL(for searchURL: URL) async throws -> URL? {
        let searchData = try await session.data(from: searchURL)
        let searchResponse = try decoder.decode(Discogs.SearchResults.self, from: searchData)
        let imageURLs: [URL] = searchResponse.results.map(\.coverImage)
        return imageURLs.first(where: { !$0.lastPathComponent.hasPrefix("spacer.gif") })
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
            let masterId: Int?
            
            enum CodingKeys: String, CodingKey {
                case coverImage = "cover_image"
                case masterId = "master_id"
            }
        }
    }
}
