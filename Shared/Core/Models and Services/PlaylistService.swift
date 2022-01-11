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
    func getPlaylist() async throws -> Playlist {
        try await self.value(for: PlaylistCacheKeys.playlist)
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
    
    @Published public private(set) var playlist: Playlist = .empty {
        didSet {
            Task {
                await cacheCoordinator.set(
                    value: playlist,
                    for: PlaylistCacheKeys.playlist,
                    lifespan: DefaultLifespan
                )
            }
        }
    }
    
    private var cacheCoordinator: CacheCoordinator
    private var cachedFetcher: PlaylistFetcher
    private var remoteFetcher: PlaylistFetcher
    private var fetchTimer: Timer? = nil
    
    private init(
        cacheCoordinator: CacheCoordinator = .WXYCPlaylist,
        cachedFetcher: PlaylistFetcher = CacheCoordinator.WXYCPlaylist,
        remoteFetcher: PlaylistFetcher = URLSession.shared
    ) {
        self.cacheCoordinator = cacheCoordinator
        self.cachedFetcher = cachedFetcher
        self.remoteFetcher = remoteFetcher
        
        self.fetchTimer = Timer(fire: Date(), interval: 30, repeats: true) { _ in
            Task { self.playlist = await self.fetchPlaylist() }
        }
        self.fetchTimer?.fire()
    }
    
    public func fetchPlaylist() async -> Playlist {
        do {
            return try await self.cachedFetcher.getPlaylist()
        } catch {
            print("No cached playlist")
        }
        
        do {
            return try await self.remoteFetcher.getPlaylist()
        } catch {
            print("Remote playlist fetch failed: \(error)")
        }
        
        return Playlist.empty
    }
    
    private func fetch(_ timer: Timer?) {
        Task {
            do {
                self.playlist = try await self.cachedFetcher.getPlaylist()
                return
            } catch {
                print("No cached playlist")
            }
            
            do {
                self.playlist = try await self.remoteFetcher.getPlaylist()
            } catch {
                print("Remote playlist fetch failed: \(error)")
            }
        }
    }
}
