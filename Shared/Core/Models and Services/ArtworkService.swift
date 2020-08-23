//
//  ArtworkService.swift
//  Core
//
//  Created by Jake Bromberg on 12/5/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import UIKit
import Combine

public final class ArtworkService {
    public static let shared = ArtworkService(fetchers: [
        CacheCoordinator.AlbumArt,
        RemoteArtworkFetcher(configuration: .discogs),
        RemoteArtworkFetcher(configuration: .lastFM),
        RemoteArtworkFetcher(configuration: .iTunes),
    ])

    private let fetchers: [ArtworkFetcher]

    private init(fetchers: [ArtworkFetcher]) {
        self.fetchers = fetchers
    }

    public func getArtwork(for playcut: Playcut) -> AnyPublisher<UIImage, Error> {
        let (first, rest) = (self.fetchers.first!, self.fetchers.dropFirst())
        return rest
            .reduce(first.fetchArtwork(for: playcut), { $0 || $1.fetchArtwork(for: playcut) })
            .eraseToAnyPublisher()
    }
}

protocol ArtworkFetcher {
    func fetchArtwork(for playcut: Playcut) -> AnyPublisher<UIImage, Error>
}

extension CacheCoordinator: ArtworkFetcher {
    func fetchArtwork(for playcut: Playcut) -> AnyPublisher<UIImage, Error> {
        return self.value(for: playcut)
            .print()
            .compactMap(UIImage.init(data:))
            .eraseToAnyPublisher()
    }
}

internal final class RemoteArtworkFetcher: ArtworkFetcher {
    internal struct Configuration {
        let makeSearchURL: (Playcut) -> URL
        let extractURL: (Data) throws -> URL
    }
    
    private let session: WebSession
    private let cacheCoordinator: CacheCoordinator
    private let configuration: Configuration
    
    private var cacheOperation: Cancellable?
    
    internal init(
        configuration: Configuration,
        cacheCoordinator: CacheCoordinator = .AlbumArt,
        session: WebSession = URLSession.shared
    ) {
        self.configuration = configuration
        self.cacheCoordinator = cacheCoordinator
        self.session = session
    }
    
    internal func fetchArtwork(for playcut: Playcut) -> AnyPublisher<UIImage, Error> {
        let downloadArtworkRequest = self
            .findArtworkURL(for: playcut)
            .flatMap(self.downloadArtwork)
            .eraseToAnyPublisher()
        
        self.cacheOperation = downloadArtworkRequest.onSuccess { image in
            self.cacheCoordinator.set(value: image.pngData(), for: playcut, lifespan: .distantFuture)
        }
        
        return downloadArtworkRequest
    }
    
    private func findArtworkURL(for playcut: Playcut) -> AnyPublisher<URL, Error> {
        let searchURLRequest = self.configuration.makeSearchURL(playcut)
        return self.session
            .dataTaskPublisher(for: searchURLRequest)
            .map(\.data)
            .tryMap(self.configuration.extractURL)
            .eraseToAnyPublisher()
    }
    
    private func downloadArtwork(at url: URL) -> AnyPublisher<UIImage, Error> {
        return self.session
            .dataTaskPublisher(for: url)
            .print()
            .tryMap { (data: Data, response: URLResponse) -> UIImage in
                guard let image = UIImage(data: data) else {
                    throw ServiceErrors.noResults
                }

                return image
            }
            .eraseToAnyPublisher()
    }
}
