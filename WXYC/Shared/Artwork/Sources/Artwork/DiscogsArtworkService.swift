import Secrets
import Logger
import Foundation
import Core
import Playlist

final class DiscogsArtworkService: ArtworkService {
    private static let key    = Secrets.discogsApiKeyV2_5
    private static let secret = Secrets.discogsApiSecretV2_5
    
    private let session: WebSession
    private let decoder = JSONDecoder()
    
    init(session: WebSession = URLSession.shared) {
        self.session = session
    }
    
    func fetchArtwork(for playcut: Playcut) async throws -> Image {
        let url: URL
        if let albumArtURL = try await fetchAlbumArtURL(for: playcut) {
            url = albumArtURL
        } else if let artistArtURL = try await fetchArtistArtURL(for: playcut) {
            url = artistArtURL
        } else {
            throw ServiceError.noResults
        }
        
        let imageData = try await session.data(from: url)
        let image = Image(data: imageData)
        
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
        
        let responseString = String(data: searchData, encoding: .utf8)
        print(responseString!)
        
        let imageURLs: [URL] = searchResponse.results.map(\.coverImage)
        return imageURLs.first(where: { !$0.lastPathComponent.hasPrefix("spacer.gif") })
    }
}

extension [URLQueryItem] {
    init(_ parameters: [String: String?]) {
        self = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
}


// MARK: - Discogs API Models

public struct Discogs {
    public struct SearchResults: Codable {
        public let results: [SearchResult]
    }
    
    public struct SearchResult: Codable {
        public let coverImage: URL
        public let masterId: Int?
        public let id: Int
        public let type: String
        public let label: [String]?
        public let year: String?
        public let uri: String?
        public let resourceUrl: String?
        
        enum CodingKeys: String, CodingKey {
            case coverImage = "cover_image"
            case masterId = "master_id"
            case id
            case type
            case label
            case year
            case uri
            case resourceUrl = "resource_url"
        }
        
        /// Constructs the full Discogs web URL from the uri field
        public var discogsWebURL: URL? {
            guard let uri = uri else { return nil }
            return URL(string: "https://www.discogs.com\(uri)")
        }
        
        /// Parsed release year as Int
        public var releaseYear: Int? {
            guard let year = year else { return nil }
            return Int(year)
        }
        
        /// First label name if available
        public var primaryLabel: String? {
            label?.first
        }
    }
    
    // MARK: - Artist Models
    
    public struct Artist: Codable {
        public let id: Int
        public let name: String
        public let profile: String?
        public let urls: [String]?
        public let images: [ArtistImage]?
        
        /// Finds Wikipedia URL from the urls array
        public var wikipediaURL: URL? {
            guard let urls = urls else { return nil }
            let wikipediaString = urls.first { url in
                url.lowercased().contains("wikipedia.org") ||
                url.lowercased().contains("en.wikipedia")
            }
            return wikipediaString.flatMap { URL(string: $0) }
        }
    }
    
    public struct ArtistImage: Codable {
        let uri: String
        let type: String
    }
    
    // MARK: - Release Models (for detailed info)
    
    public struct Release: Codable {
        let id: Int
        let title: String
        let year: Int?
        let labels: [Label]?
        let artists: [ReleaseArtist]?
        let uri: String?
        
        struct Label: Codable {
            let name: String
            let id: Int
        }
        
        struct ReleaseArtist: Codable {
            let id: Int
            let name: String
        }
        
        public var primaryLabel: String? {
            labels?.first?.name
        }
        
        public var primaryArtistId: Int? {
            artists?.first?.id
        }
        
        public var discogsWebURL: URL? {
            guard let uri = uri else { return nil }
            return URL(string: "https://www.discogs.com\(uri)")
        }
    }
    
    // MARK: - Master Release Models
    
    public struct Master: Codable {
        let id: Int
        let title: String
        let year: Int?
        let uri: String?
        let artists: [ReleaseArtist]?
        
        struct ReleaseArtist: Codable {
            let id: Int
            let name: String
        }
        
        public var primaryArtistId: Int? {
            artists?.first?.id
        }
        
        public var discogsWebURL: URL? {
            guard let uri = uri else { return nil }
            return URL(string: "https://www.discogs.com\(uri)")
        }
    }
}
