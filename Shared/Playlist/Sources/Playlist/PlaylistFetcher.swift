//
//  PlaylistFetcher.swift
//  Playlist
//
//  Protocol and implementation for fetching playlist data.
//
//  Created by Jake Bromberg on 11/10/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Core
import Logger
import PostHog
import Analytics

// MARK: - Protocols

/// Protocol for fetching playlists (non-throwing, returns empty on error).
public protocol PlaylistFetcherProtocol: Sendable {
    func fetchPlaylist() async -> Playlist
}

/// Protocol for raw playlist data fetching (throws on error).
/// Used internally by PlaylistFetcher and for testing.
public protocol PlaylistDataSource: Sendable {
    func getPlaylist() async throws -> Playlist
}

/// Protocol for analytics capturing, allowing PostHogSDK to be mocked in tests.
public protocol PlaylistAnalytics: AnyObject {
    func capture(_ event: String, context: String?, additionalData: [String: String])
    func capture(error: String, code: Int, context: String, additionalData: [String: String])
    func capture(error: AnalyticsOSError, context: String, additionalData: [String: String])
    func capture(error: AnalyticsDecoderError, context: String, additionalData: [String: String])
}

// MARK: - PostHogSDK Conformance

extension PostHogSDK: PlaylistAnalytics {
    // Conformance is satisfied by the extensions in Analytics module
}

// MARK: - URLSession Playlist Fetching

private let decoder = JSONDecoder()

extension URLSession: PlaylistDataSource {
    public func getPlaylist() async throws -> Playlist {
        do {
            let (playlistData, _) = try await self.data(from: URL.WXYCPlaylist)
            let repairedData = playlistData.repairingMojibake()
            return try decoder.decode(Playlist.self, from: repairedData)
        } catch let error as NSError {
            print(error.localizedDescription)
            throw AnalyticsOSError(
                domain: error.domain,
                code: error.code,
                description: error.localizedDescription
            )
        } catch let error as DecodingError {
            throw AnalyticsDecoderError(description: error.localizedDescription)
        }
    }
}

extension Data {
    /// Repairs mojibake caused by UTF-8 text being stored/sent as Latin-1.
    ///
    /// The V1 API server has encoding issues where UTF-8 characters are corrupted
    /// (e.g., "Björk" becomes "BjÃ¶rk"). This repairs by re-interpreting the
    /// UTF-8 string as Latin-1 bytes, then decoding those bytes as UTF-8.
    func repairingMojibake() -> Data {
        guard let string = String(data: self, encoding: .utf8),
              let latin1Data = string.data(using: .isoLatin1),
              let repaired = String(data: latin1Data, encoding: .utf8),
              let repairedData = repaired.data(using: .utf8) else {
            return self
        }
        return repairedData
    }
}

// MARK: - PlaylistFetcher

/// Fetches playlists from a remote source with logging and analytics.
/// Wraps a PlaylistDataSource with error handling, logging, and analytics tracking.
public final class PlaylistFetcher: PlaylistFetcherProtocol, @unchecked Sendable {
    private let dataSource: PlaylistDataSource
    private let analytics: PlaylistAnalytics
    private let apiVersion: PlaylistAPIVersion

    /// Creates a new PlaylistFetcher.
    ///
    /// - Parameters:
    ///   - apiVersion: The API version to use. If nil, uses `PlaylistAPIVersion.loadActive()`.
    ///   - dataSource: Custom data source. If nil, creates one based on apiVersion.
    ///   - analytics: Analytics service for logging.
    public init(
        apiVersion: PlaylistAPIVersion? = nil,
        dataSource: PlaylistDataSource? = nil,
        analytics: PlaylistAnalytics = PostHogSDK.shared
    ) {
        let resolvedVersion = apiVersion ?? PlaylistAPIVersion.loadActive()
        self.apiVersion = resolvedVersion
        self.dataSource = dataSource ?? Self.createDataSource(for: resolvedVersion)
        self.analytics = analytics
    }

    /// Creates the appropriate data source for the given API version.
    private static func createDataSource(for version: PlaylistAPIVersion) -> PlaylistDataSource {
        switch version {
        case .v1:
            URLSession.shared
        case .v2:
            PlaylistDataSourceV2()
        }
    }

    /// Fetches a playlist from the remote source.
    /// Returns an empty playlist if the fetch fails.
    public func fetchPlaylist() async -> Playlist {
        Log(.info, category: .network, "Fetching remote playlist (API \(apiVersion.rawValue))")
        let timer = Core.Timer.start()
        do {
            let playlist = try await self.dataSource.getPlaylist()
            let duration = timer.duration()
            Log(.info, category: .network, "Remote playlist fetch succeeded: fetch time \(duration), entry count \(playlist.entries.count)")

            // Simplified sampling: 10% of requests
            if Int.random(in: 1...10) == 1 {
                analytics.capture("fetchPlaylist", context: nil, additionalData: ["duration":"\(duration)"])
            }

            return playlist
        } catch is CancellationError {
            // Task was cancelled - this is normal during cleanup
            return Playlist.empty
        } catch let error as NSError {
            let duration = timer.duration()
            Log(.error, category: .network, "Remote playlist fetch failed after \(duration) seconds: \(error)")
            analytics.capture(
                error: error.localizedDescription,
                code: error.code,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        } catch let error as AnalyticsOSError {
            let duration = timer.duration()
            Log(.error, category: .network, "Remote playlist fetch failed after \(duration) seconds: \(error)")
            analytics.capture(
                error: error,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        } catch let error as AnalyticsDecoderError {
            let duration = timer.duration()
            Log(.error, category: .network, "Remote playlist fetch failed after \(duration) seconds: \(error)")
            analytics.capture(
                error: error,
                context: "fetchPlaylist",
                additionalData: ["duration":"\(duration)"]
            )

            return Playlist.empty
        }
    }
}
