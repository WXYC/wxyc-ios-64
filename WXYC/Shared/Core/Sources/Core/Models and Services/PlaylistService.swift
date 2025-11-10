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

public final actor PlaylistService: Sendable, AsyncSequence {
    public typealias Element = Playlist

    private let remoteFetcher: PlaylistFetcher
    private let interval: TimeInterval
    private var currentPlaylist: Playlist = .empty

    public init(
        remoteFetcher: PlaylistFetcher = URLSession.shared,
        interval: TimeInterval = 30
    ) {
        self.remoteFetcher = remoteFetcher
        self.interval = interval
    }

    public nonisolated func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(service: self)
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        private let service: PlaylistService
        private var hasYieldedInitial = false
        private var lastPlaylist: Playlist?

        init(service: PlaylistService) {
            self.service = service
        }

        public mutating func next() async -> Playlist? {
            // Sleep at the start of each iteration (except the first)
            if hasYieldedInitial {
                try? await Task.sleep(for: .seconds(service.interval))
            }

            // On first call, yield the current cached value immediately if available
            if !hasYieldedInitial {
                hasYieldedInitial = true
                let current = await service.currentPlaylist
                lastPlaylist = current

                // If we have a non-empty playlist, yield it immediately
                if !current.entries.isEmpty {
                    return current
                }
                // If empty, fall through to fetch a new one
            }

            // Fetch a new playlist
            let playlist = await service.fetchAndUpdatePlaylist()

            // Only yield if the playlist has changed
            if let last = lastPlaylist, playlist == last {
                // Playlist hasn't changed, recursively try again (will sleep at top of next iteration)
                Log(.info, "No change in playlist, waiting \(service.interval) seconds")
                return await next()
            } else {
                // Playlist has changed, update and return immediately
                lastPlaylist = playlist
                return playlist
            }
        }
    }

    /// Fetch a playlist and update the cached current value
    private func fetchAndUpdatePlaylist() async -> Playlist {
        let playlist = await fetchPlaylist()
        currentPlaylist = playlist
        return playlist
    }

    public func fetchPlaylist() async -> Playlist {
        Log(.info, "Fetching remote playlist")
        let startTime = Date.timeIntervalSinceReferenceDate
        do {
            let playlist = try await self.remoteFetcher.getPlaylist()
            let duration = Date.timeIntervalSinceReferenceDate - startTime
            Log(.info, "Remote playlist fetch succeeded: fetch time \(duration), entry count \(playlist.entries.count)")
            return playlist
        } catch let error as NSError {
            let duration = Date.timeIntervalSinceReferenceDate - startTime
            Log(.error, "Remote playlist fetch failed after \(duration) seconds: \(error)")
            PostHogSDK.shared.capture(
                error: error.localizedDescription,
                code: error.code,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        } catch let error as AnalyticsOSError {
            let duration = Date.timeIntervalSinceReferenceDate - startTime
            Log(.error, "Remote playlist fetch failed after \(duration) seconds: \(error)")
            PostHogSDK.shared.capture(
                error: error,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        } catch let error as AnalyticsDecoderError {
            let duration = Date.timeIntervalSinceReferenceDate - startTime
            Log(.error, "Remote playlist fetch failed after \(duration) seconds: \(error)")
            PostHogSDK.shared.capture(
                error: error,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        }
    }
}
