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

// MARK: - URLSession Playlist Fetching

extension URLSession: PlaylistDataSource {
    public func getPlaylist() async throws -> Playlist {
        let (playlistData, response) = try await self.data(from: URL.WXYCPlaylist)
        try (response as? HTTPURLResponse)?.validateSuccessStatus()
        let repairedData = playlistData.repairingMojibake()
        return try JSONDecoder.shared.decode(Playlist.self, from: repairedData)
    }
}

extension Data {
    /// Repairs mojibake caused by UTF-8 text being stored/sent as Latin-1.
    ///
    /// The V1 API server has encoding issues where UTF-8 characters are corrupted
    /// (e.g., "Bjork" becomes "BjÃ¶rk"). This repairs by re-interpreting the
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
    private let errorReporter: any ErrorReporter
    private let analytics: any AnalyticsService
    private let apiVersion: PlaylistAPIVersion

    /// Creates a new PlaylistFetcher.
    ///
    /// - Parameters:
    ///   - apiVersion: The API version to use. If nil, uses `PlaylistAPIVersion.loadActive()`.
    ///   - dataSource: Custom data source. If nil, creates one based on apiVersion.
    ///   - errorReporter: Error reporter for failure tracking. Defaults to the global reporter.
    ///   - analytics: Analytics service for event tracking.
    public init(
        apiVersion: PlaylistAPIVersion? = nil,
        dataSource: PlaylistDataSource? = nil,
        errorReporter: any ErrorReporter = ErrorReporting.shared,
        analytics: any AnalyticsService = StructuredPostHogAnalytics.shared
    ) {
        let resolvedVersion = apiVersion ?? PlaylistAPIVersion.loadActive()
        self.apiVersion = resolvedVersion
        self.dataSource = dataSource ?? Self.createDataSource(for: resolvedVersion)
        self.errorReporter = errorReporter
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
        let timer = Core.Timer.start()

        let playlist = await timedOperation(
            context: "fetchPlaylist(API \(apiVersion.rawValue))",
            category: .network,
            fallback: .empty,
            errorReporter: errorReporter
        ) {
            try await self.dataSource.getPlaylist()
        }

        // TODO: move to PostHog server-side sampling
        if playlist != .empty, Int.random(in: 1...10) == 1 {
            analytics.capture(FetchPlaylistEvent(duration: timer.duration()))
        }

        return playlist
    }
}
