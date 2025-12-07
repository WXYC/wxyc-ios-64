//
//  RemotePlaylistFetcher.swift
//  Core
//
//  Created by Jake Bromberg on 11/24/25.
//

import Foundation
import Core
import Logger
import PostHog
import Analytics

/// Fetches playlists from a remote source with logging and analytics.
/// Wraps a PlaylistFetcher protocol implementation and adds error handling,
/// logging, and analytics tracking.
open class RemotePlaylistFetcher: @unchecked Sendable {
    private let remoteFetcher: PlaylistFetcher

    public init(remoteFetcher: PlaylistFetcher = URLSession.shared) {
        self.remoteFetcher = remoteFetcher
    }

    /// Fetches a playlist from the remote source.
    /// Returns an empty playlist if the fetch fails.
    open func fetchPlaylist() async -> Playlist {
        Log(.info, "Fetching remote playlist")
        let timer = Core.Timer.start()
        do {
            let playlist = try await self.remoteFetcher.getPlaylist()
            let duration = timer.duration()
            Log(.info, "Remote playlist fetch succeeded: fetch time \(duration), entry count \(playlist.entries.count)")

            // Simplified sampling: 10% of requests
            if Int.random(in: 1...10) == 1 {
                PostHogSDK.shared.capture("fetchPlaylist", additionalData: ["duration":"\(duration)"])
            }

            return playlist
        } catch is CancellationError {
            // Task was cancelled - this is normal during cleanup
            return Playlist.empty
        } catch let error as NSError {
            let duration = timer.duration()
            Log(.error, "Remote playlist fetch failed after \(duration) seconds: \(error)")
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
            PostHogSDK.shared.capture(
                error: error,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        } catch let error as AnalyticsDecoderError {
            let duration = timer.duration()
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
