//
//  ArtworkService.swift
//  Core
//
//  Created by Jake Bromberg on 12/5/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import UIKit

public final class ArtworkService {
    private let cache: Cachable
    private let session: WebSession
    
    init(cache: Cachable = Cache.WXYC, session: WebSession = URLSession.shared) {
        self.cache = cache
        self.session = session
    }
    
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        return self.getCachedArtwork()
            || self.getNetworkArtwork(for: playcut)
            || self.getDefaultArtwork()
    }
    
    private func getCachedArtwork() -> Future<UIImage> {
        let dataRequest: Future<Data> = self.cache.getCachedValue(key: .artwork)
        let imageRequest: Future<UIImage> =  dataRequest.transformed(with: UIImage.init)
        
        return imageRequest
    }
    
    private func getNetworkArtwork(for playcut: Playcut) -> Future<UIImage> {
        let urlRequest = self.getArtworkURL(for: playcut)
        let imageRequest = urlRequest.chained(with: self.getArtwork(at:))
        
        imageRequest.onSuccess { image in
            Cache.WXYC[CacheKey.artwork] = image.pngData()
        }
        
        return imageRequest
    }
    
    private func getArtworkURL(for playcut: Playcut) -> Future<URL> {
        return self.getLastFMArtworkURL(for: playcut) || self.getItunesArtworkURL(for: playcut)
    }
    
    private func getDefaultArtwork() -> Future<UIImage> {
        return Promise(value: #imageLiteral(resourceName: "logo"))
    }
    
    private func getArtwork(at url: URL) -> Future<UIImage> {
        return self.session.request(url: url)
            .chained(with: { data -> Future<UIImage> in
                return Promise(value: UIImage(data: data))
            })
    }
    
    private func getItunesArtworkURL(for playcut: Playcut) -> Future<URL> {
        let url = iTunes.searchURL(for: playcut)
        return self.session.request(url: url)
            .transformed(with: { data -> URL in
                let decoder = JSONDecoder()
                let results = try decoder.decode(iTunes.SearchResults.self, from: data)
                
                if let item = results.results.first {
                    return item.artworkUrl100
                } else {
                    throw ServiceErrors.noResults
                }
            })
    }
    
    private func getLastFMArtworkURL(for playcut: Playcut) -> Future<URL> {
        let lastFMURL = LastFM.searchURL(for: playcut)
        return self.session.request(url: lastFMURL)
            .transformed(with: { data -> URL in
                let decoder = JSONDecoder()
                let searchResponse = try decoder.decode(LastFM.SearchResponse.self, from: data)
                
                return searchResponse.album.largestAlbumArt.url
            })
    }
}
