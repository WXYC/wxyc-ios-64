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

public final actor ArtworkService {
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

    public func getArtwork(for playcut: Playcut) async -> UIImage? {
        for fetcher in self.fetchers {
            do {
                return try await fetcher.fetchArtwork(for: playcut)
            } catch {
                print(">>> No artwork found for \(playcut) using fetcher \(fetcher)")
            }
        }
        
        return nil
    }
}

protocol ArtworkFetcher {
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage
}

extension CacheCoordinator: ArtworkFetcher {
    func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let cachedData: Data = try await self.value(for: playcut)
        guard let artwork = UIImage(data: cachedData) else {
            throw ServiceErrors.noCachedResult
        }
        
        return artwork
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
    
    internal func fetchArtwork(for playcut: Playcut) async throws -> UIImage {
        let artworkURL = try await self.findArtworkURL(for: playcut)
        let artwork = try await self.downloadArtwork(at: artworkURL)
        
        Task {
            await self.cacheCoordinator.set(value: artwork.pngData(), for: playcut, lifespan: .distantFuture)
        }
        
        return artwork
    }
    
    private func findArtworkURL(for playcut: Playcut) async throws -> URL {
        let searchURLRequest = self.configuration.makeSearchURL(playcut)
        let (data, _) = try await URLSession.shared.data(from: searchURLRequest)
        return try self.configuration.extractURL(data)
    }
    
    private func downloadArtwork(at url: URL) async throws -> UIImage {
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let image = UIImage(data: data) else {
            throw ServiceErrors.noResults
        }
        
        return image
    }
}
