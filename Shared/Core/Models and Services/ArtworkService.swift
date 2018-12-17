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
    public static let shared = ArtworkService(fetchers: [
        CachedArtworkFetcher(cacheCoordinator: .AlbumArt),
        RemoteArtworkFetcher<DiscogsConfiguration>(),
        RemoteArtworkFetcher<LastFMConfiguration>(),
        RemoteArtworkFetcher<iTunesConfiguration>(),
        DefaultArtworkFetcher()
    ])
    
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
    let cacheCoordinator: CacheCoordinator
    
    init(cacheCoordinator: CacheCoordinator = .WXYCPlaylist) {
        self.cacheCoordinator = cacheCoordinator
    }
    
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        let request: Future<Data> = self.cacheCoordinator.getValue(for: playcut)
        
        request.observe { result in
            if case let .error(error) = result {
                print(error)
            }
        }
        
        return request.transformed(with: UIImage.init(data:))
    }
}

final class DefaultArtworkFetcher: ArtworkFetcher {
    static let defaultArtworkPromise = Promise(value: #imageLiteral(resourceName: "logo"))
    
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        return DefaultArtworkFetcher.defaultArtworkPromise
    }
}

protocol RemoteArtworkFetcherConfiguration {
    static func makeSearchURL(for playcut: Playcut) -> URL
    static func extractURL(from data: Data) throws -> URL
}

final class RemoteArtworkFetcher<Configuration: RemoteArtworkFetcherConfiguration>: ArtworkFetcher {
    let session: WebSession
    let cacheCoordinator: CacheCoordinator
    
    init(cacheCoordinator: CacheCoordinator = .AlbumArt, session: WebSession = URLSession.shared) {
        self.cacheCoordinator = cacheCoordinator
        self.session = session
    }
    
    func getArtwork(for playcut: Playcut) -> Future<UIImage> {
        let searchURLRequest = Configuration.makeSearchURL(for: playcut)
        let imageURLRequest = self.session.request(url: searchURLRequest)
            .transformed(with: Configuration.extractURL(from:))
        let downloadImageRequest = imageURLRequest.chained(with: self.getArtwork(at:))
        
        downloadImageRequest.onSuccess { image in
            self.cacheCoordinator.set(value: image.pngData(), for: playcut, lifespan: .distantFuture)
        }
        
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
                
        return imageRequest
    }
}
