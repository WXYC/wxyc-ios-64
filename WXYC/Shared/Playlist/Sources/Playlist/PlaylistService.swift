//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import Logger
import Caching

public final actor PlaylistService: Sendable {
    private let fetcher: PlaylistFetcherProtocol
    private let interval: TimeInterval
    private var currentPlaylist: Playlist = .empty
    private var fetchTask: Task<Void, Never>?
    private let cacheCoordinator: CacheCoordinator
    private static let cacheKey = "com.wxyc.playlist.cache"
    private static let cacheLifespan: TimeInterval = 15 * 60 // 15 minutes
    
    /// Collection of continuations for broadcasting to multiple observers
    private var continuations: [UUID: AsyncStream<Playlist>.Continuation] = [:]

    public init(
        fetcher: PlaylistFetcherProtocol = PlaylistFetcher(),
        interval: TimeInterval = 30,
        cacheCoordinator: CacheCoordinator = CacheCoordinator.Playlist
    ) {
        self.fetcher = fetcher
        self.interval = interval
        self.cacheCoordinator = cacheCoordinator
        Task {
            await loadCachedPlaylist()
        }
    }
    
    /// Load cached playlist if available and not expired
    private func loadCachedPlaylist() async {
        do {
            let cachedPlaylist: Playlist = try await cacheCoordinator.value(for: Self.cacheKey)
            currentPlaylist = cachedPlaylist
            // Broadcast cached data to any existing observers
            broadcast(cachedPlaylist)
            Log(.info, "Loaded cached playlist with \(cachedPlaylist.entries.count) entries")
        } catch {
            Log(.info, "No valid cached playlist available")
        }
    }
    
    /// Fetch playlist and cache it, always fetching fresh data (ignores cache).
    /// Used for background refresh to ensure we always get the latest data.
    public func fetchAndCachePlaylist() async -> Playlist {
        // Always fetch fresh data, ignoring cache
        let playlist = await fetcher.fetchPlaylist()

        // Cache the fresh playlist (this will overwrite any existing cache)
        await cacheCoordinator.set(value: playlist, for: Self.cacheKey, lifespan: Self.cacheLifespan)

        // Update current playlist and broadcast if changed
        if playlist != currentPlaylist {
            currentPlaylist = playlist
            broadcast(playlist)
        }

        Log(.info, "Fetched and cached playlist with \(playlist.entries.count) entries")
        return playlist
    }

    /// Direct fetch method for widgets and extensions that need immediate data.
    /// First checks the cache, and if cache is empty or expired, fetches from network.
    /// This method is designed for widget timeline providers that have strict time constraints.
    public func fetchPlaylist() async -> Playlist {
        // Try to get cached playlist first
        do {
            let cachedPlaylist: Playlist = try await cacheCoordinator.value(for: Self.cacheKey)
            Log(.info, "Returning cached playlist with \(cachedPlaylist.entries.count) entries")
            return cachedPlaylist
        } catch {
            // Cache miss or expired - fetch from network
            Log(.info, "Cache miss, fetching fresh playlist")
            let playlist = await fetcher.fetchPlaylist()

            // Cache the result for future use
            await cacheCoordinator.set(value: playlist, for: Self.cacheKey, lifespan: Self.cacheLifespan)

            Log(.info, "Fetched and cached new playlist with \(playlist.entries.count) entries")
            return playlist
        }
    }

    /// Returns an AsyncStream that yields playlist updates.
    /// If a cached playlist exists, it's yielded immediately.
    /// Otherwise, observers wait for the first fetch to complete.
    /// Multiple observers each receive their own stream of updates.
    public nonisolated func updates() -> AsyncStream<Playlist> {
        let id = UUID()
        
        return AsyncStream { continuation in
            let setupTask = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                
                await self.addContinuation(continuation, for: id)
            }
            
            continuation.onTermination = { @Sendable [weak self] _ in
                setupTask.cancel()
                
                guard let self else { return }
                
                Task {
                    await self.removeContinuation(for: id)
                }
            }
        }
    }
    
    private func addContinuation(_ continuation: AsyncStream<Playlist>.Continuation, for id: UUID) {
        continuations[id] = continuation
        
        // Yield current cache immediately if non-empty
        if currentPlaylist != .empty {
            continuation.yield(currentPlaylist)
        }
        
        // Start fetching if not already running
        ensureFetchTaskRunning()
    }
    
    private func removeContinuation(for id: UUID) {
        continuations.removeValue(forKey: id)
        
        // Stop fetching if no more observers
        if continuations.isEmpty {
            cancelFetchTask()
        }
    }
    
    /// Broadcast a playlist update to all observers
    private func broadcast(_ playlist: Playlist) {
        for continuation in continuations.values {
            continuation.yield(playlist)
        }
    }

    private func cancelFetchTask() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    deinit {
        for continuation in continuations.values {
            continuation.finish()
        }
        fetchTask?.cancel()
    }

    /// Ensure the fetch task is running
    private func ensureFetchTaskRunning() {
        guard fetchTask == nil else { return }

        fetchTask = Task {
            await startFetching()
        }
    }

    /// Single background fetch loop shared by all observers
    private func startFetching() async {
        while !Task.isCancelled {
            let playlist = await fetcher.fetchPlaylist()
            
            // Cache the fetched playlist
            await cacheCoordinator.set(value: playlist, for: Self.cacheKey, lifespan: Self.cacheLifespan)

            guard !Task.isCancelled else { break }

            // Only broadcast if changed
            if playlist != currentPlaylist {
                currentPlaylist = playlist
                broadcast(playlist)
            }

            guard !Task.isCancelled else { break }

            try? await Task.sleep(for: .seconds(interval))
        }
    }
}
