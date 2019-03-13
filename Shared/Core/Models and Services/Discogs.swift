//
//  Discogs.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/7/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation

struct Discogs {
    struct SearchResults: Codable {
        let results: [Results]
        
        struct Results: Codable {
            let coverImage: URL
        }
    }
}

final class DiscogsConfiguration: RemoteArtworkFetcherConfiguration {
    static func makeSearchURL(for playcut: Playcut) -> URL {
        let key    = "tYvsaskeJxOQbWoZSSkh"
        let secret = "vZuPZFFDerXIPrBfSNnNyDhXjpIUiyXi"
        
        var components = URLComponents(string: "https://api.discogs.com")!
        components.path = "/database/search"
        components.queryItems = [
            URLQueryItem(name: "artist",  value: playcut.artistName),
            URLQueryItem(name: "album",   value: playcut.releaseTitle),
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "secret", value: secret),
        ]
        
        return components.url!
    }
    
    static func extractURL(from data: Data) throws -> URL {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let searchResponse = try decoder.decode(Discogs.SearchResults.self, from: data)
        
        guard let albumURL = searchResponse.results.first?.coverImage else {
            throw ServiceErrors.noResults
        }
        
        return albumURL
    }
}
