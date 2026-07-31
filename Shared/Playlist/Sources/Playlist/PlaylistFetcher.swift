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
    ///
    /// Handled inline (rather than via `timedOperation`) so the success, failure,
    /// and cancellation outcomes are all distinguishable in one place: only a
    /// genuine failure reports to the error reporter and counts against the
    /// success/failure denominator, and the API version is threaded onto the
    /// report as a structured `api_version` property.
    public func fetchPlaylist() async -> Playlist {
        let timer = Core.Timer.start()
        let context = "fetchPlaylist(API \(apiVersion.rawValue))"

        do {
            let playlist = try await dataSource.getPlaylist()
            let duration = timer.duration()
            Log(.info, category: .network, "\(context): succeeded in \(duration)s")
            // A task cancelled after the data already arrived is not a real
            // outcome; keep it out of the success/failure denominator.
            if !Task.isCancelled {
                captureFetchEvent(playlist: playlist, succeeded: true, duration: duration)
            }
            return playlist
        } catch {
            // `URLSession.data(for:)` throws `URLError(.cancelled)` (NOT Swift's
            // `CancellationError`) when a fetch is torn down — e.g. switchAPIVersion
            // swapping the data source mid-flight — and it can surface without the
            // task's `isCancelled` flag being set. Cancellation is normal teardown:
            // don't report it to the error reporter (Sentry) and don't count it as
            // a failure in the rollout metric.
            if isCancellation(error) || Task.isCancelled {
                return .empty
            }

            let duration = timer.duration()
            errorReporter.report(
                error,
                context: context,
                category: .network,
                additionalData: [
                    "api_version": apiVersion.rawValue,
                    "duration": "\(duration)",
                ]
            )
            captureFetchEvent(playlist: .empty, succeeded: false, duration: duration)
            return .empty
        }
    }

    /// Emits a `FetchPlaylistEvent` for a terminal fetch outcome.
    ///
    /// Sampling policy (resolving the old `// TODO: move to PostHog server-side
    /// sampling`): empty results and failures are rare and high-signal, so they
    /// are always captured. Only the high-volume, low-signal healthy (non-empty)
    /// success path keeps the legacy 1-in-10 client sample.
    ///
    /// That means TWO of the three outcomes carry `succeeded = true` but are
    /// sampled at different rates, so a naive `count(succeeded)` is biased two
    /// ways at once: non-empty successes are under-counted 10x, empty successes
    /// are not. `result_count` separates them — it is `entries.count`, which is 0
    /// exactly when the playlist is content-empty (the sampler gates on
    /// `isContentEmpty`, and `entries` is the same four arrays it inspects). To
    /// recover a true per-variant weighted success count in PostHog (filter on
    /// `api_version`):
    ///
    ///     weighted_success = 10 * count(succeeded && result_count > 0)   // sampled 1-in-10
    ///                      +      count(succeeded && result_count == 0)  // unsampled, ×1
    ///
    /// The ×10 applies ONLY to non-empty successes; empty successes are already
    /// full-rate and must be added back at ×1, not multiplied and not dropped.
    /// The success rate is then
    /// `weighted_success / (weighted_success + count(succeeded == false))`.
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
