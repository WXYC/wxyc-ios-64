//
//  ArtworkService.swift
//  Core
//
//  Created by Jake Bromberg on 12/5/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import UIKit

final class ArtworkService {
    private let cache: Cachable
    private let session: WebSession
    
    let fetchers: [ArtworkFetcher]
    
    init(cache: Cachable = Cache.WXYC, session: WebSession = URLSession.shared) {
        self.cache = cache
        self.session = session
        
        self.fetchers = [
            CachedArtworkFetcher(cache: self.cache),
            RemoteArtworkFetcher(locator: DiscogsLocator()),
            RemoteArtworkFetcher(locator: LastFMLocator()),
            RemoteArtworkFetcher(locator: iTunesLocator()),
            DefaultArtworkFetcher()
        ]
    }
    
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        let (first, rest) = (self.fetchers.first!, self.fetchers.dropFirst())
        return rest.reduce(first.getArtwork(for: playcut), { $0 || $1.getArtwork(for: playcut) })
    }
}

protocol ArtworkFetcher {
    func getArtwork(for playcut: Playcut) -> Future<UIImage>
}

final class CachedArtworkFetcher: ArtworkFetcher {
    let cache: Cachable
    
    init(cache: Cachable = Cache.WXYC) {
        self.cache = cache
    }
    
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        let dataRequest: Future<Data> = self.cache.getCachedValue(key: .artwork)
        let imageRequest: Future<UIImage> =  dataRequest.transformed(with: UIImage.init)
        
        return imageRequest
    }
}

final class DefaultArtworkFetcher: ArtworkFetcher {
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        return Promise(value: #imageLiteral(resourceName: "logo"))
    }
}

protocol RemoteArtworkLocator {
    func makeSearchURL(for playcut: Playcut) -> URL
    func extractURL(from data: Data) throws -> URL
}

final class RemoteArtworkFetcher: ArtworkFetcher {
    let session: WebSession
    let cache: Cachable
    let locator: RemoteArtworkLocator
    
    init(cache: Cachable = Cache.WXYC, session: WebSession = URLSession.shared, locator: RemoteArtworkLocator) {
        self.cache = cache
        self.session = session
        self.locator = locator
    }
    
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        let searchURLRequest = self.locator.makeSearchURL(for: playcut)
        let imageURLRequest = self.session.request(url: searchURLRequest)
            .transformed(with: self.locator.extractURL(from:))
        let downloadImageRequest = imageURLRequest.chained(with: self.getArtwork(at:))
        
        return downloadImageRequest
    }
    
    private func getArtwork(at url: URL) -> Future<UIImage> {
        let imageRequest = self.session.request(url: url)
            .transformed(with: { data -> UIImage in
                guard let image = UIImage(data: data) else {
                    throw ServiceErrors.noResults
                }
                
                return image
            })
        
        imageRequest.onSuccess { image in
            self.cache[CacheKey.artwork] = image.pngData()
        }
        
        return imageRequest
    }
}
