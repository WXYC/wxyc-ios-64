//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation

public final actor PlaylistService: Sendable {
    private let fetcher: RemotePlaylistFetcher
    private let interval: TimeInterval
    private var currentPlaylist: Playlist = .empty
    private var fetchTask: Task<Void, Never>?
    
    /// Collection of continuations for broadcasting to multiple observers
    private var continuations: [UUID: AsyncStream<Playlist>.Continuation] = [:]

    public init(
        fetcher: RemotePlaylistFetcher = RemotePlaylistFetcher(),
        interval: TimeInterval = 30
    ) {
        self.fetcher = fetcher
        self.interval = interval
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
