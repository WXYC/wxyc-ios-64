//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import Observation

protocol PlaylistFetcher: Sendable {
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
        let string = String(data: playlistData, encoding: .utf8)
        print(string)
        let decoder = JSONDecoder()
        return try decoder.decode(Playlist.self, from: playlistData)
    }
}

@Observable
public final class PlaylistService: @unchecked Sendable {
    public static let shared = PlaylistService()
    
    @ObservationTracked public private(set) var playlist: Playlist 
    @ObservationIgnored private var _playlist: Playlist = .empty {
        didSet {
            let registrar = self._$observationRegistrar
            registrar.didSet(self, keyPath: \.playlist)
        }
    }
    @ObservationIgnored private let accessorQueue = DispatchQueue(label: "PlaylistService")
    
    @ObservationIgnored private let cacheCoordinator: CacheCoordinator
    @ObservationIgnored private let cachedFetcher: PlaylistFetcher
    @ObservationIgnored private let remoteFetcher: PlaylistFetcher
    @ObservationIgnored private let fetchTimer: DispatchSource?
    
    init(
        cacheCoordinator: CacheCoordinator = .WXYCPlaylist,
        cachedFetcher: PlaylistFetcher = CacheCoordinator.WXYCPlaylist,
        remoteFetcher: PlaylistFetcher = URLSession.shared
    ) {
        self.cacheCoordinator = cacheCoordinator
        self.cachedFetcher = cachedFetcher
        self.remoteFetcher = remoteFetcher
        
        self.fetchTimer = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.global(qos: .default)) as? DispatchSource
        self.fetchTimer?.schedule(deadline: .now(), repeating: 30)
        self.fetchTimer?.setEventHandler {
            Task {
                let playlist = await self.fetchPlaylist()
                
                assert(playlist != .empty)
                
                guard await playlist != self.playlist else {
                    return
                }
                
                await self.set(playlist: playlist)
                await self.cacheCoordinator.set(
                    value: self.playlist,
                    for: CacheCoordinator.playlistKey,
                    lifespan: DefaultLifespan
                )
            }
        }
        self.fetchTimer?.resume()
    }
    
    private func set(playlist: Playlist) async {
        self.playlist = playlist
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
            print(">>> Fetching remote playlist")
            let startTime = Date.timeIntervalSinceReferenceDate
            let playlist = try await self.remoteFetcher.getPlaylist()
            let duration = Date.timeIntervalSinceReferenceDate - startTime
            print(">>> Remote playlist fetch succeeded: fetch time \(duration), entry count \(playlist.entries.count)")
            return playlist
        } catch {
            print(">>> Remote playlist fetch failed: \(error)")
        }
        
        return Playlist.empty
    }
}
