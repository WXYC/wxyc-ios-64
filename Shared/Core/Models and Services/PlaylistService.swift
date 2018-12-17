//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation

public class PlaylistService {
    private var cacheCoordinator: CacheCoordinator
    private let webSession: WebSession
    private var playlistRequest: Future<Playlist>?
    
    init(cacheCoordinator: CacheCoordinator = .WXYCPlaylist, webSession: WebSession = URLSession.shared) {
        self.cacheCoordinator = cacheCoordinator
        self.webSession = webSession
        
        self.playlistRequest = Future.repeat({ self.getCachedPlaylist() || self.getRemotePlaylist() })
    }

    public static let shared = PlaylistService()
    
    public func getPlaylist() -> Future<Playlist> {
        return self.playlistRequest!
    }
    
    private func getCachedPlaylist() -> Future<Playlist> {
        let request: Future<Playlist> =
            self.cacheCoordinator.getValue(for: PlaylistCacheKeys.playlist)
        
        request.observe { result in
            if case let .error(error) = result {
                print(error)
            }
        }
        
        return request
    }

    private func getRemotePlaylist() -> Future<Playlist> {
        return self.webSession.request(url: URL.WXYCPlaylist).transformed { data -> Playlist in
            let decoder = JSONDecoder()
            let playlist = try decoder.decode(Playlist.self, from: data)
            
            self.cacheCoordinator.set(
                value: playlist,
                for: PlaylistCacheKeys.playlist,
                lifespan: DefaultLifespan
            )
            
            return playlist
        }
    }
}
