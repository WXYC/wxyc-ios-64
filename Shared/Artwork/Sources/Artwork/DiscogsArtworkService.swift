//
//  DiscogsArtworkService.swift
//  Artwork
//
//  Fetches album artwork via the backend proxy endpoint.
//  Falls back gracefully when no token provider is available.
//
//  Created by Jake Bromberg on 04/12/23.
//  Copyright © 2023 WXYC. All rights reserved.
//

import Foundation
import Core
import CoreGraphics
import Playlist

final class DiscogsArtworkService: ArtworkService {
    private let baseURL: URL
    private let tokenProvider: SessionTokenProvider?
    private let session: WebSession
    private let decoder = JSONDecoder()

    init(
        baseURL: URL = URL(string: "https://api.wxyc.org")!,
        tokenProvider: SessionTokenProvider? = nil,
        session: WebSession = URLSession.shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.session = session
    }

    func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        var components = URLComponents(url: baseURL.appending(path: "proxy/artwork/search"), resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "artistName", value: playcut.artistName)]

        if let releaseTitle = playcut.releaseTitle {
            let title = releaseTitle.lowercased() == "s/t" ? playcut.artistName : releaseTitle
            queryItems.append(URLQueryItem(name: "releaseTitle", value: title))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw ServiceError.noResults
        }

        // The backend proxy now returns image bytes directly (with NSFW filtering
        // applied server-side), so we no longer need to parse a JSON response and
        // download the image in a separate step.
        let imageData: Data
        if let tokenProvider {
            let token = try await tokenProvider.token()
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
                throw ServiceError.noResults
            }

            imageData = data
        } else {
            imageData = try await session.data(from: url)
        }

        guard let cgImage = createCGImage(from: imageData) else {
            throw ServiceError.noResults
        }

        return cgImage
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

        /// Constructs the full Discogs web URL from the uri field or id/type
        public var discogsWebURL: URL? {
            // Prefer uri if available
            if let uri {
                return URL(string: "https://www.discogs.com\(uri)")
            }

            // Fallback: construct URL from type and id
            let path: String
            switch type {
            case "release":
                path = "/release/\(id)"
            case "master":
                path = "/master/\(id)"
            case "artist":
                path = "/artist/\(id)"
            case "label":
                path = "/label/\(id)"
            default:
                path = "/\(type)/\(id)"
            }

            return URL(string: "https://www.discogs.com\(path)")
        }

        /// Parsed release year as Int
        public var releaseYear: Int? {
            guard let year else { return nil }
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
            guard let urls else { return nil }
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
            guard let uri else { return nil }
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
            guard let uri else { return nil }
            return URL(string: "https://www.discogs.com\(uri)")
        }
    }
}
