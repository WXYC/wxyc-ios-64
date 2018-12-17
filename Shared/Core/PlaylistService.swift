//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation

public class PlaylistService {
    private var cache: Cache
    private let webSession: WebSession
    private var playlistRequest: Future<Playlist>?
    
    init(cache: Cache = .WXYC, webSession: WebSession = URLSession.shared) {
        self.cache = cache
        self.webSession = webSession
        
        self.playlistRequest = Future.repeat({ self.getCachedPlaylist() || self.getRemotePlaylist() })
    }

    public static let shared = PlaylistService()
    
    public func getPlaylist() -> Future<Playlist> {
        return self.playlistRequest!
    }
    
    private func getCachedPlaylist() -> Future<Playlist> {
        if let playlist: Playlist = self.cache[CacheKey.playlist] {
            return Promise(value: playlist)
        } else {
            return Promise(error: ServiceErrors.noCachedResult)
        }
    }

    private func getRemotePlaylist() -> Future<Playlist> {
        return self.webSession.request(url: URL.WXYCPlaylist).transformed { data -> Playlist in
            let decoder = JSONDecoder()
            let playlist = try decoder.decode(Playlist.self, from: data)
            
            self.cache[CacheKey.playlist] = playlist
            
            return playlist
        }
    }
}
