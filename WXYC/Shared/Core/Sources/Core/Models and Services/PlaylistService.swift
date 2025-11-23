//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import Logger
import PostHog
import SwiftUI
import Analytics

public final actor PlaylistService: Sendable {
    private let remoteFetcher: PlaylistFetcher
    private let interval: TimeInterval
    private var currentPlaylist: Playlist = .empty
    private var continuations: [UUID: AsyncStream<Playlist>.Continuation] = [:]
    private var fetchTask: Task<Void, Never>?

    public init(
        remoteFetcher: PlaylistFetcher = URLSession.shared,
        interval: TimeInterval = 30
    ) {
        self.remoteFetcher = remoteFetcher
        self.interval = interval
    }

    /// Returns an AsyncStream that immediately yields the current cached playlist,
    /// then yields updates whenever the playlist changes.
    /// Multiple observers share a single fetch cycle.
    public nonisolated func updates() -> AsyncStream<Playlist> {
        return AsyncStream { continuation in
            let id = UUID()
            
            // Start fetch task and register continuation
            Task { [weak self] in
                guard let self else { return }
                
                // Start the fetch task if not already running
                if await self.fetchTask == nil {
                    await self.startFetchTask()
                }
                
                // Immediately yield current cached value
                let current = await self.currentPlaylist
                continuation.yield(current)
                
                // Register for future updates
                await self.registerContinuation(id: id, continuation: continuation)
            }
            
            // Clean up on termination
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }
    
    private func startFetchTask() {
        fetchTask = Task { await startFetching() }
    }
    
    private func registerContinuation(id: UUID, continuation: AsyncStream<Playlist>.Continuation) {
        continuations[id] = continuation
    }
    
    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Single background fetch loop shared by all observers
    private func startFetching() async {
        while !Task.isCancelled {
            let playlist = await fetchPlaylist()
            
            // Only broadcast if changed
            if playlist != currentPlaylist {
                currentPlaylist = playlist
                broadcast(playlist)
            }
            
            try? await Task.sleep(for: .seconds(interval))
        }
    }
    
    /// Broadcast playlist update to all active observers
    private func broadcast(_ playlist: Playlist) {
        for (_, continuation) in continuations {
            continuation.yield(playlist)
        }
    }

    public func fetchPlaylist() async -> Playlist {
        Log(.info, "Fetching remote playlist")
        let timer = Timer.start()
        do {
            let playlist = try await self.remoteFetcher.getPlaylist()
            let duration = timer.duration()
            Log(.info, "Remote playlist fetch succeeded: fetch time \(duration), entry count \(playlist.entries.count)")
            
            if (1...10).randomElement() ?? 1 % 10 == 0 {
                PostHogSDK.shared.capture("fetchPlaylist", additionalData: ["duration":"\(duration)"])
            }
            
            return playlist
        } catch let error as NSError {
            let duration = timer.duration()
            Log(.error, "Remote playlist fetch failed after \(duration) seconds: \(error)")
            assert(duration > 0.01)
            PostHogSDK.shared.capture(
                error: error.localizedDescription,
                code: error.code,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        } catch let error as AnalyticsOSError {
            let duration = timer.duration()
            Log(.error, "Remote playlist fetch failed after \(duration) seconds: \(error)")
            assert(duration > 0.01)
            PostHogSDK.shared.capture(
                error: error,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        } catch let error as AnalyticsDecoderError {
            let duration = timer.duration()
            Log(.error, "Remote playlist fetch failed after \(duration) seconds: \(error)")
            assert(duration > 0.01)
            PostHogSDK.shared.capture(
                error: error,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        }
    }
}
