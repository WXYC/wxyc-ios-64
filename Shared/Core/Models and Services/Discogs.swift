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

extension RemoteArtworkFetcher.Configuration {
    static var discogs = Self(makeSearchURL: { playcut in
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
    }, extractURL: { data in
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let searchResponse = try decoder.decode(Discogs.SearchResults.self, from: data)
        let imageURLs: [URL] = searchResponse.results.map(\.coverImage)
        
        for url in imageURLs {
            if !url.lastPathComponent.hasSuffix("spacer.gif") {
                return url
            }
        }
        
        throw ServiceErrors.noResults
    })
}
