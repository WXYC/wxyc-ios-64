//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import Combine

protocol PlaylistFetcher {
    func getPlaylist() -> AnyPublisher<Playlist, Error>
}

extension CacheCoordinator: PlaylistFetcher {
    func getPlaylist() -> AnyPublisher<Playlist, Error> {
        return self.value(for: PlaylistCacheKeys.playlist)
    }
}

extension URLSession: PlaylistFetcher {
    func getPlaylist() -> AnyPublisher<Playlist, Error> {
        let decoder = JSONDecoder()
        return self.dataTaskPublisher(for: URL.WXYCPlaylist)
            .map { (data, _) in data }
            .decode(type: Playlist.self, decoder: decoder)
            .eraseToAnyPublisher()
    }
}

public class PlaylistService {
    public static let shared = PlaylistService()
    
    @Published public private(set) var playlist: Playlist = .empty {
        didSet {
            cacheCoordinator.set(
                value: playlist,
                for: PlaylistCacheKeys.playlist,
                lifespan: DefaultLifespan
            )
        }
    }
    
    private var cacheCoordinator: CacheCoordinator
    private var cacheSink: Cancellable? = nil
    
    private init(
        cacheCoordinator: CacheCoordinator = .WXYCPlaylist,
        cachedFetcher: PlaylistFetcher = CacheCoordinator.WXYCPlaylist,
        remoteFetcher: PlaylistFetcher = URLSession.shared
    ) {
        self.cacheCoordinator = cacheCoordinator
        self.cacheSink = (cachedFetcher.getPlaylist() || remoteFetcher.getPlaylist())
            .onSuccess({ [weak self] playlist in
                self?.playlist = playlist
            })
    }
}
