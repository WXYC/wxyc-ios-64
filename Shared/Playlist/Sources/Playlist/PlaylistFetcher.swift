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

// MARK: - Data Repair

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
    private let healthySuccessSampler: @Sendable () -> Bool

    /// Creates a new PlaylistFetcher.
    ///
    /// - Parameters:
    ///   - apiVersion: The API version to use. If nil, uses `PlaylistAPIVersion.loadActive()`.
    ///   - dataSource: Custom data source. If nil, creates one based on apiVersion.
    ///   - errorReporter: Error reporter for failure tracking. Defaults to the global reporter.
    ///   - analytics: Analytics service for event tracking.
    ///   - healthySuccessSampler: Decides whether a healthy (non-empty) success
    ///     emits its `fetch_playlist_event`. Defaults to a per-call 1-in-10 coin
    ///     flip so the high-volume, low-signal success path stays sampled. Empty
    ///     results and failures ignore this gate and are always captured. Injected
    ///     for deterministic tests.
    public init(
        apiVersion: PlaylistAPIVersion? = nil,
        dataSource: PlaylistDataSource? = nil,
        errorReporter: any ErrorReporter = ErrorReporting.shared,
        analytics: any AnalyticsService = StructuredPostHogAnalytics.shared,
        healthySuccessSampler: @escaping @Sendable () -> Bool = { Int.random(in: 1...10) == 1 }
    ) {
        let resolvedVersion = apiVersion ?? PlaylistAPIVersion.loadActive()
        self.apiVersion = resolvedVersion
        self.dataSource = dataSource ?? Self.createDataSource(for: resolvedVersion)
        self.errorReporter = errorReporter
        self.analytics = analytics
        self.healthySuccessSampler = healthySuccessSampler
    }

    /// Creates the appropriate data source for the given API version.
    private static func createDataSource(for version: PlaylistAPIVersion) -> PlaylistDataSource {
        switch version {
        case .v1:
            PlaylistDataSourceV1()
        case .v2:
            PlaylistDataSourceV2()
        }
    }

    /// Fetches a playlist from the remote source.
    /// Returns an empty playlist if the fetch fails.
    public func fetchPlaylist() async -> Playlist {
        let timer = Core.Timer.start()

        // Fetch through an optional so success is distinguishable from the
        // failure/cancellation fallback: `timedOperation` returns `.some` only
        // when the operation completes, and `nil` when it throws or is cancelled.
        // The version rides `additionalData` so a reported failure carries a
        // structured `api_version` property, not just the free-text context.
        let fetched: Playlist? = await timedOperation(
            context: "fetchPlaylist(API \(apiVersion.rawValue))",
            category: .network,
            fallback: nil,
            errorReporter: errorReporter,
            additionalData: ["api_version": apiVersion.rawValue]
        ) {
            try await self.dataSource.getPlaylist()
        }

        let playlist = fetched ?? .empty
        let succeeded = fetched != nil

        // A cancelled fetch (normal task teardown) also returns nil but is not a
        // real outcome — `timedOperation` swallows `CancellationError` without
        // reporting it. Keep it out of the success/failure denominator.
        if succeeded || !Task.isCancelled {
            captureFetchEvent(playlist: playlist, succeeded: succeeded, duration: timer.duration())
        }

        return playlist
    }

    /// Emits a `FetchPlaylistEvent` for a terminal fetch outcome.
    ///
    /// Sampling policy (resolving the old `// TODO: move to PostHog server-side
    /// sampling`): empty results and failures are rare and high-signal, so they
    /// are always captured. Only the high-volume, low-signal healthy (non-empty)
    /// success path keeps the legacy 1-in-10 client sample. To recover a true
    /// success rate in PostHog, weight the non-empty `succeeded = true` count by
    /// 10 before dividing.
    private func captureFetchEvent(playlist: Playlist, succeeded: Bool, duration: TimeInterval) {
        let isHealthySuccess = succeeded && !playlist.isContentEmpty
        guard !isHealthySuccess || healthySuccessSampler() else { return }

        analytics.capture(FetchPlaylistEvent(
            duration: duration,
            apiVersion: apiVersion.rawValue,
            resultCount: playlist.entries.count,
            succeeded: succeeded
        ))
    }
}
