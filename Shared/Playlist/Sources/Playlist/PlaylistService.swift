//
//  PlaylistService.swift
//  Playlist
//
//  Main service for fetching and caching playlists with periodic updates and multi-observer
//  broadcasting via AsyncStream. Provides cache-aware fetching for widgets and extensions.
//
//  Created by Jake Bromberg on 12/17/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import Logger
import Caching

public final actor PlaylistService: Sendable {
    private var fetcher: PlaylistFetcherProtocol
    private let interval: TimeInterval
    private var currentPlaylist: Playlist = .empty
    private var fetchTask: Task<Void, Never>?
    private let cacheCoordinator: CacheCoordinator
    private static let cacheKey = "com.wxyc.playlist.cache"
    private static let cacheLifespan: TimeInterval = 15 * 60 // 15 minutes
    
    /// Collection of continuations for broadcasting to multiple observers
    private var continuations: [UUID: AsyncStream<Playlist>.Continuation] = [:]
    
    /// Task that loads the initial cached playlist. Awaited before first yield to prevent
    /// race conditions where observers subscribe before cache is loaded.
    /// 
    /// Note: This is marked `nonisolated(unsafe)` because it's assigned once during `init`
    /// (which is nonisolated in actors) and only read afterwards. This is safe because:
    /// 1. The write happens before any async work can read it
    /// 2. Task is a reference type and the reference itself doesn't change after init
    private nonisolated(unsafe) var cacheLoadTask: Task<Void, Never>?
    
    /// Whether the initial cache load has completed. Used to avoid awaiting the task
    /// on subsequent subscriptions.
    private var cacheLoaded = false

    public init(
        fetcher: PlaylistFetcherProtocol = PlaylistFetcher(),
        interval: TimeInterval = 30,
        cacheCoordinator: CacheCoordinator = CacheCoordinator.Playlist
    ) {
        self.fetcher = fetcher
        self.interval = interval
        self.cacheCoordinator = cacheCoordinator
        
        // Start loading cached playlist immediately.
        // Observers will await this task before receiving their first value.
        cacheLoadTask = Task { [self] in
            await self.loadCachedPlaylist()
        }
    }
    
    /// Load cached playlist if available and not expired.
    /// Called once at initialization.
    private func loadCachedPlaylist() async {
        defer { cacheLoaded = true }
        
        do {
            let cachedPlaylist: Playlist = try await cacheCoordinator.value(for: Self.cacheKey)
            currentPlaylist = cachedPlaylist
            // Broadcast cached data to any existing observers
            broadcast(cachedPlaylist)
            Log(.info, category: .network, "Loaded cached playlist with \(cachedPlaylist.entries.count) entries")
        } catch {
            Log(.info, category: .network, "No valid cached playlist available")
        }
    }
    
    /// Check if the cached playlist has expired or doesn't exist.
    /// Used to determine if a foreground refresh is needed.
    public func isCacheExpired() async -> Bool {
        do {
            // Attempt to read from cache - this will throw if expired or missing
            let _: Playlist = try await cacheCoordinator.value(for: Self.cacheKey)
            return false
        } catch {
            return true
        }
    }
    
    /// Waits for the initial cache load to complete.
    ///
    /// The service automatically loads cached data at initialization.
    /// This method allows callers to await that operation's completion.
    public func waitForCacheLoad() async {
        if !cacheLoaded {
            await cacheLoadTask?.value
        }
    }
    
    /// Fetch playlist and cache it, always fetching fresh data (ignores cache).
    /// Used for background refresh to ensure we always get the latest data.
    ///
    /// Important: This method does NOT replace valid data with empty playlists.
    /// If the fetch fails (returning `.empty`), existing cached data is preserved.
    public func fetchAndCachePlaylist() async -> Playlist {
        // Always fetch fresh data, ignoring cache
        let playlist = await fetcher.fetchPlaylist()
        
        // Only cache and broadcast non-empty playlists, OR if we don't have any data yet.
        // This prevents network errors (which return .empty) from clearing valid cached data.
        let shouldUpdate = playlist != .empty || currentPlaylist == .empty

        if shouldUpdate {
            // Cache the fresh playlist (this will overwrite any existing cache)
            await cacheCoordinator.set(value: playlist, for: Self.cacheKey, lifespan: Self.cacheLifespan)

            // Update current playlist and broadcast if changed
            if playlist != currentPlaylist {
                currentPlaylist = playlist
                broadcast(playlist)
            }

            Log(.info, category: .network, "Fetched and cached playlist with \(playlist.entries.count) entries \(playlist.entries)")
        } else {
            Log(.warning, category: .network, "Ignoring empty playlist from background refresh - keeping existing data with \(currentPlaylist.entries.count) entries")
        }
        
        // Return the fetched playlist (may be empty), but in-memory state is preserved
        return playlist
    }

    /// Direct fetch method for widgets and extensions that need immediate data.
    /// First checks the cache, and if cache is empty or expired, fetches from network.
    /// This method is designed for widget timeline providers that have strict time constraints.
    public func fetchPlaylist() async -> Playlist {
        // Try to get cached playlist first
        do {
            let cachedPlaylist: Playlist = try await cacheCoordinator.value(for: Self.cacheKey)
            Log(.info, category: .network, "Returning cached playlist with \(cachedPlaylist.entries.count) entries")
            return cachedPlaylist
        } catch {
            // Cache miss or expired - fetch from network
            Log(.info, category: .network, "Cache miss, fetching fresh playlist")
            let playlist = await fetcher.fetchPlaylist()

            // Cache the result for future use
            await cacheCoordinator.set(value: playlist, for: Self.cacheKey, lifespan: Self.cacheLifespan)

            Log(.info, category: .network, "Fetched and cached new playlist with \(playlist.entries.count) entries")
            return playlist
        }
    }

    /// Switches to a different API version and immediately fetches fresh data.
    /// Clears the current playlist and cache before fetching to ensure clean data.
    ///
    /// - Parameter version: The API version to switch to.
    public func switchAPIVersion(to version: PlaylistAPIVersion) async {
        Log(.info, category: .network, "Switching playlist API to \(version.rawValue)")
            
        // Cancel any existing fetch task
        cancelFetchTask()
                
        // Create new fetcher with the specified version
        fetcher = PlaylistFetcher(apiVersion: version)

        // Clear current playlist to show loading state
        currentPlaylist = .empty
        broadcast(.empty)
            
        // Fetch fresh data with new API version (this will overwrite the cache)
        _ = await fetchAndCachePlaylist()
                
        // Restart fetch loop if we have observers
        if !continuations.isEmpty {
            ensureFetchTaskRunning()
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
        
    private func addContinuation(_ continuation: AsyncStream<Playlist>.Continuation, for id: UUID) async {
        continuations[id] = continuation
        
        // Wait for initial cache load to complete before deciding whether to yield.
        // This prevents a race condition where observers subscribe before the cache
        // is loaded, causing them to see an empty playlist until the network fetch completes.
        if !cacheLoaded {
            await cacheLoadTask?.value
        }
        
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

    /// Single background fetch loop shared by all observers.
    /// 
    /// Important: This method intentionally does NOT broadcast empty playlists when we already
    /// have valid data. This prevents transient network errors from clearing the UI. The fetcher
    /// returns `.empty` on any error (network timeout, server error, etc.), so without this
    /// protection, a temporary network issue would replace good cached data with nothing.
    private func startFetching() async {
        while !Task.isCancelled {
            let playlist = await fetcher.fetchPlaylist()

            // Only cache and broadcast non-empty playlists, OR if we don't have any data yet.
            // This prevents network errors (which return .empty) from clearing valid cached data.
            let shouldUpdate = playlist != .empty || currentPlaylist == .empty

            if shouldUpdate {
                // Cache the fetched playlist
                await cacheCoordinator.set(value: playlist, for: Self.cacheKey, lifespan: Self.cacheLifespan)

                guard !Task.isCancelled else { break }

                // Only broadcast if changed
                if playlist != currentPlaylist {
                    currentPlaylist = playlist
                    broadcast(playlist)
                }
            } else {
                Log(.warning, category: .network, "Ignoring empty playlist from fetch - keeping existing data with \(currentPlaylist.entries.count) entries")
            }

            guard !Task.isCancelled else { break }

            try? await Task.sleep(for: .seconds(interval))
        }
    }
}
