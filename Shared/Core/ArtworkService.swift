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
    public static var shared: ArtworkService = {
        return ArtworkService(fetchers: [
            CachedArtworkFetcher(cache: .WXYC),
            RemoteArtworkFetcher<DiscogsConfiguration>(),
            RemoteArtworkFetcher<LastFMConfiguration>(),
            RemoteArtworkFetcher<iTunesConfiguration>(),
            DefaultArtworkFetcher()
        ])
    }()
    
    private let fetchers: [ArtworkFetcher]
    
    private init(fetchers: [ArtworkFetcher]) {
        self.fetchers = fetchers
    }
    
    public func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        let (first, rest) = (self.fetchers.first!, self.fetchers.dropFirst())
        return rest.reduce(first.getArtwork(for: playcut), { $0 || $1.getArtwork(for: playcut) })
    }
}

protocol ArtworkFetcher {
    func getArtwork(for playcut: Playcut) -> Future<UIImage>
}

final class CachedArtworkFetcher: ArtworkFetcher {
    let cache: Cache
    
    init(cache: Cache = .WXYC) {
        self.cache = cache
    }
    
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        return self.cache[playcut].transformed(with: UIImage.init(data:))
    }
}

final class DefaultArtworkFetcher: ArtworkFetcher {
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        return Promise(value: #imageLiteral(resourceName: "logo"))
    }
}

protocol RemoteArtworkFetcherConfiguration {
    static func makeSearchURL(for playcut: Playcut) -> URL
    static func extractURL(from data: Data) throws -> URL
}

final class RemoteArtworkFetcher<Configuration: RemoteArtworkFetcherConfiguration>: ArtworkFetcher {
    let session: WebSession
    let cache: Cache
    
    init(cache: Cache = .WXYC, session: WebSession = URLSession.shared) {
        self.cache = cache
        self.session = session
    }
    
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        let searchURLRequest = Configuration.makeSearchURL(for: playcut)
        let imageURLRequest = self.session.request(url: searchURLRequest)
            .transformed(with: Configuration.extractURL(from:))
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
            self.cache[url] = image.pngData()
        }
        
        return imageRequest
    }
}
