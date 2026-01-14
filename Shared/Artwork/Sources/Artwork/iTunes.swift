//
//  iTunes.swift
//  Artwork
//
//  iTunes Search API types and artwork service for fetching album art.
//
//  Created by Jake Bromberg on 11/03/17.
//  Copyright © 2017 WXYC. All rights reserved.
//

import Foundation
import Core
import CoreGraphics
import Playlist

final class iTunesArtworkService: ArtworkService {
    private let session: WebSession
    private let decoder = JSONDecoder()

    init(session: WebSession = URLSession.shared) {
        self.session = session
    }

    func fetchArtwork(for playcut: Playcut) async throws -> CGImage {
        let searchURL = makeSearchURL(for: playcut)
        let searchData = try await session.data(from: searchURL)
        let results = try decoder.decode(iTunes.SearchResults.self, from: searchData)

        guard let result = results.results.first else {
            throw ServiceError.noResults
        }
        
        let imageData = try await session.data(from: result.artworkUrl100)
        
        guard let cgImage = createCGImage(from: imageData) else {
            throw ServiceError.noResults
        }
        
        return cgImage
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
