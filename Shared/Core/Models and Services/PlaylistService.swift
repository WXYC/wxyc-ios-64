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

public final class PlaylistService: @unchecked Sendable {
    public static let shared = PlaylistService()
    
    @Publishable public private(set) var playlist: Playlist
    
    private let cacheCoordinator: CacheCoordinator
    private let cachedFetcher: PlaylistFetcher
    private let remoteFetcher: PlaylistFetcher
    private let fetchTimer: DispatchSource?
    
    init(
        cacheCoordinator: CacheCoordinator = .WXYCPlaylist,
        cachedFetcher: PlaylistFetcher = CacheCoordinator.WXYCPlaylist,
        remoteFetcher: PlaylistFetcher = URLSession.shared
    ) {
        self.cacheCoordinator = cacheCoordinator
        self.cachedFetcher = cachedFetcher
        self.remoteFetcher = remoteFetcher
        
        self.playlist = .empty
        
        self.fetchTimer = DispatchSource.makeTimerSource(flags: [], queue: DispatchQueue.global(qos: .default)) as? DispatchSource
        self.fetchTimer?.schedule(deadline: .now(), repeating: 30)
        self.fetchTimer?.setEventHandler {
            Task {
                let playlist = await self.fetchPlaylist()
                
                guard playlist != self.playlist else {
                    return
                }
                
                if playlist.entries.isEmpty {
                    print("Empty playlist")
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
        print(">>> Fetching remote playlist")
        let startTime = Date.timeIntervalSinceReferenceDate
        do {
            let playlist = try await self.remoteFetcher.getPlaylist()
            let duration = Date.timeIntervalSinceReferenceDate - startTime
            print(">>> Remote playlist fetch succeeded: fetch time \(duration), entry count \(playlist.entries.count)")
            return playlist
        } catch {
            let duration = Date.timeIntervalSinceReferenceDate - startTime
            print(">>> Remote playlist fetch failed after \(duration) seconds: \(error)")
        }
        
        return Playlist.empty
    }
}

final class DevPlaylistFetcher: PlaylistFetcher {
    func getPlaylist() async throws -> Playlist {
        Playlist(
            playcuts: [Fixture.playcut1, Fixture.playcut2],
            breakpoints: [],
            talksets: []
        )
    }
    
    enum Fixture {
        static let playcut1 = Playcut(
            id: 1768545,
            hour: 1518408000000,
            chronOrderID: 146173021,
            songTitle: "Dancing Queen",
            labelName: "Atlantic",
            artistName: "ABBA",
            releaseTitle: "Dancing queen 7"
        )
        
        static let playcut2 = Playcut(
            id: 1768705,
            hour: 1518444000000,
            chronOrderID: 146179020,
            songTitle: "Left Fields",
            labelName: "INTERNATIONAL ANTHEM RECORDING COMPANY",
            artistName: "Makaya McCraven",
            releaseTitle: "Highly Rare"
        )
    }
}
