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
import Synchronization

// MARK: - Protocols

/// Protocol for fetching playlists (non-throwing, returns empty on error).
public protocol PlaylistFetcherProtocol: Sendable {
    func fetchPlaylist() async -> Playlist

    /// Cumulative count of `fetchPlaylist()` calls that failed (network error,
    /// HTTP error, or decode failure) and fell back to an empty playlist,
    /// since this fetcher instance was created. Cancellation is excluded,
    /// matching the exclusion already applied to the error-reporter and
    /// analytics paths in `PlaylistFetcher.fetchPlaylist()`.
    ///
    /// For observability only (see WXYC/wxyc-ios-64#267): `fetchPlaylist()`'s
    /// return value and the caller's behavior are unchanged by this count.
    /// Defaults to zero for conformers that don't track failures — test
    /// doubles in particular, which return a configured playlist rather than
    /// modeling a real network round trip.
    var fetchErrorCount: Int { get }
}

extension PlaylistFetcherProtocol {
    public var fetchErrorCount: Int { 0 }
}

/// Protocol for raw playlist data fetching (throws on error).
/// Used internally by PlaylistFetcher and for testing.
public protocol PlaylistDataSource: Sendable {
    func getPlaylist() async throws -> Playlist
}

// MARK: - PlaylistFetcher

/// Fetches playlists from a remote source with logging and analytics.
/// Wraps a PlaylistDataSource with error handling, logging, and analytics tracking.
public final class PlaylistFetcher: PlaylistFetcherProtocol, @unchecked Sendable {
    private let dataSource: PlaylistDataSource
    private let errorReporter: any ErrorReporter
    private let analytics: any AnalyticsService
    private let healthySuccessSampler: @Sendable () -> Bool

    /// Backing store for ``fetchErrorCount``. A `Mutex`, not a plain `Int`,
    /// because `fetchPlaylist()` can genuinely run concurrently — the polling
    /// loop in `PlaylistService.startFetching()` and an SSE `.refetch` handler
    /// can both be in flight against the same fetcher at once — and a plain
    /// increment would be a data race under real parallelism, not just actor
    /// reentrancy.
    private let failureCount = Mutex(0)

    /// The value reported as `api_version` on `fetch_playlist_event` and on
    /// error reports.
    ///
    /// A constant rather than a resolved enum since the v1 path was removed
    /// (#262). It stays on the wire rather than being dropped because App
    /// Store builds through 3.2 still poll the legacy `wxyc.info` feed and
    /// report `v1`, so the property is the only thing separating those two
    /// populations in PostHog. Retire it once that cohort has drained.
    private static let apiVersionTag = "v2"

    /// Creates a new PlaylistFetcher.
    ///
    /// - Parameters:
    ///   - dataSource: Custom data source. If nil, polls the v2 flowsheet API.
    ///   - errorReporter: Error reporter for failure tracking. Defaults to the global reporter.
    ///   - analytics: Analytics service for event tracking.
    ///   - healthySuccessSampler: Decides whether a healthy (non-empty) success
    ///     emits its `fetch_playlist_event`. Defaults to a per-call 1-in-10 coin
    ///     flip so the high-volume, low-signal success path stays sampled. Empty
    ///     results and failures ignore this gate and are always captured. Injected
    ///     for deterministic tests.
    public init(
        dataSource: PlaylistDataSource? = nil,
        errorReporter: any ErrorReporter = ErrorReporting.shared,
        analytics: any AnalyticsService = StructuredPostHogAnalytics.shared,
        healthySuccessSampler: @escaping @Sendable () -> Bool = { Int.random(in: 1...10) == 1 }
    ) {
        self.dataSource = dataSource ?? PlaylistDataSourceV2()
        self.errorReporter = errorReporter
        self.analytics = analytics
        self.healthySuccessSampler = healthySuccessSampler
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
        let context = "fetchPlaylist(API \(Self.apiVersionTag))"

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
            // `CancellationError`) when a fetch is torn down — e.g. a service
            // teardown cancelling the poll loop mid-flight — and it can surface without the
            // task's `isCancelled` flag being set. Cancellation is normal teardown:
            // don't report it to the error reporter (Sentry) and don't count it as
            // a failure in the rollout metric.
            if isCancellation(error) || Task.isCancelled {
                return .empty
            }

            failureCount.withLock { $0 += 1 }

            let duration = timer.duration()
            errorReporter.report(
                error,
                context: context,
                category: .network,
                additionalData: [
                    "api_version": Self.apiVersionTag,
                    "duration": "\(duration)",
                ]
            )
            captureFetchEvent(playlist: .empty, succeeded: false, duration: duration)
            return .empty
        }
    }

    /// See ``PlaylistFetcherProtocol/fetchErrorCount``.
    public var fetchErrorCount: Int {
        failureCount.withLock { $0 }
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
            apiVersion: Self.apiVersionTag,
            resultCount: playlist.entries.count,
            succeeded: succeeded
        ))
    }
}
