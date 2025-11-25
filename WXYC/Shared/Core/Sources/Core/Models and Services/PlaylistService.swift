//
//  PlaylistService.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/15/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation
import Synchronization

public final actor PlaylistService: Sendable {
    private let fetcher: RemotePlaylistFetcher
    private let interval: TimeInterval
    private var currentPlaylist: Playlist = .empty
    private var fetchTask: Task<Void, Never>?
    private let playlistStream: AsyncStream<Playlist>
    private let continuation: AsyncStream<Playlist>.Continuation
    private let observerCount = Atomic<Int>(0)

    public init(
        fetcher: RemotePlaylistFetcher = RemotePlaylistFetcher(),
        interval: TimeInterval = 30
    ) {
        self.fetcher = fetcher
        self.interval = interval

        // Create single stream with single continuation
        var cont: AsyncStream<Playlist>.Continuation!
        self.playlistStream = AsyncStream { continuation in
            cont = continuation
        }
        self.continuation = cont
    }

    /// Returns an AsyncStream that yields playlist updates.
    /// If a cached playlist exists, it's yielded immediately.
    /// Otherwise, observers wait for the first fetch to complete.
    /// Multiple observers share a single stream.
    public nonisolated func updates() -> AsyncStream<Playlist> {
        // Return a new stream that wraps the shared stream and tracks lifecycle
        return AsyncStream { continuation in
            let observerTask = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }

                // Atomically increment observer count
                self.observerCount.wrappingAdd(1, ordering: .relaxed)
                await self.ensureFetchTaskRunning()

                // Forward all values from shared stream to this continuation
                for await playlist in self.playlistStream {
                    continuation.yield(playlist)
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable [weak self] _ in
                observerTask.cancel()

                guard let self else { return }

                // Atomically decrement and check if zero (synchronously!)
                let newCount = self.observerCount.wrappingSubtract(1, ordering: .relaxed)
                if newCount.newValue == 0 {
                    Task {
                        await self.cancelFetchTask()
                    }
                }
            }
        }
    }

    private func cancelFetchTask() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    deinit {
        continuation.finish()
        fetchTask?.cancel()
    }

    /// Atomically ensure the fetch task is running
    private func ensureFetchTaskRunning() {
        guard fetchTask == nil else { return }

        fetchTask = Task {
            await startFetching()
        }
    }

    /// Single background fetch loop shared by all observers
    private func startFetching() async {
        // Yield current cache if non-empty
        if currentPlaylist != .empty {
            continuation.yield(currentPlaylist)
        }

        while !Task.isCancelled {
            let playlist = await fetcher.fetchPlaylist()

            guard !Task.isCancelled else { break }

            // Only broadcast if changed
            if playlist != currentPlaylist {
                currentPlaylist = playlist
                continuation.yield(playlist)
            }

            guard !Task.isCancelled else { break }

            try? await Task.sleep(for: .seconds(interval))
        }
    }
}
