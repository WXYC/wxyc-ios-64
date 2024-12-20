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
    func getPlaylist() async throws -> Playlist
}

extension CacheCoordinator: PlaylistFetcher {
    static let playlistKey = "playlist"
    
    func getPlaylist() async throws -> Playlist {
        try await self.value(for: CacheCoordinator.playlistKey)
    }
}

extension URLSession: PlaylistFetcher {
    func getPlaylist() async throws -> Playlist {
        let (playlistData, _) = try await self.data(from: URL.WXYCPlaylist)
        let decoder = JSONDecoder()
        return try decoder.decode(Playlist.self, from: playlistData)
    }
}

public class PlaylistService {
    public static let shared = PlaylistService()
    
    @Published public private(set) var playlist: Playlist = .empty
    
    private var cacheCoordinator: CacheCoordinator
    private var cachedFetcher: PlaylistFetcher
    private var remoteFetcher: PlaylistFetcher
    private var fetchTimer: DispatchSourceTimer? = nil
    
    private init(
        cacheCoordinator: CacheCoordinator = .WXYCPlaylist,
        cachedFetcher: PlaylistFetcher = CacheCoordinator.WXYCPlaylist,
        remoteFetcher: PlaylistFetcher = URLSession.shared
    ) {
        self.cacheCoordinator = cacheCoordinator
        self.cachedFetcher = cachedFetcher
        self.remoteFetcher = remoteFetcher
        
        self.fetchTimer = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.global(qos: .default))
        self.fetchTimer?.schedule(deadline: .now(), repeating: 30)
        self.fetchTimer?.setEventHandler {
            Task {
                let playlist = await self.fetchPlaylist()
                
                guard playlist != self.playlist else {
                    return
                }
                
                self.playlist = playlist
                await self.cacheCoordinator.set(
                    value: self.playlist,
                    for: CacheCoordinator.playlistKey,
                    lifespan: DefaultLifespan
                )
            }
        }
        self.fetchTimer?.resume()
    }
    
    deinit {
        self.fetchTimer?.cancel()
    }
    
    public func fetchPlaylist(forceSync: Bool = false) async -> Playlist {
        print(">>> fetching playlist async")

        if !forceSync {
            do {
                return try await self.cachedFetcher.getPlaylist()
            } catch {
                print(">>> No cached playlist")
            }
        }
        
        do {
            return try await self.remoteFetcher.getPlaylist()
        } catch {
            print(">>> Remote playlist fetch failed: \(error)")
        }
        
        return Playlist.empty
    }
}
