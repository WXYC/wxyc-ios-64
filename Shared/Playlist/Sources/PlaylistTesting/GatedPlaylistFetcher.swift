//
//  GatedPlaylistFetcher.swift
//  PlaylistTesting
//
//  Test double for PlaylistFetcherProtocol whose fetchPlaylist() parks until the
//  test releases it. Parking on a non-throwing withCheckedContinuation makes it
//  cancellation-inert, which is what lets a test hold PlaylistService's live-updates
//  consume loop at a fixed point and drive reentrant calls against it deterministically
//  — no Task.sleep, no wall-clock deadline, no blocked thread. See WXYC/wxyc-ios-64#749.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Synchronization
@_exported import Playlist

/// Test double for ``PlaylistFetcherProtocol`` that suspends inside
/// ``fetchPlaylist()`` until the test calls ``release()``.
///
/// The park is a non-throwing `withCheckedContinuation`, which has no
/// cancellation handling — so a task suspended here does **not** resume when it
/// is cancelled. That is the point: `PlaylistService.consumeLiveEvents` reaches
/// this seam via `applyLiveEvent(.refetch)` → `fetchAndCachePlaylist()`, so a
/// scripted `.refetch` event parks the consume loop somewhere cancellation
/// cannot move it, and `switchAPIVersion(to:)`'s `await liveUpdatesTask?.value`
/// then stays suspended for exactly as long as the test wants.
///
/// ```swift
/// let fetcher = GatedPlaylistFetcher(playlist: .stub(playcuts: [.stub(id: 1)]))
/// let source = MockLiveFsEventSource(events: [.refetch(source: "etl")])
/// let service = PlaylistService(
///     fetcher: fetcher, cacheCoordinator: makeTestCacheCoordinator(),
///     liveEventSource: source, apiVersion: .v2
/// )
/// await service.setForegrounded(true)
/// await fetcher.waitForEntry()   // consume loop is now parked
/// // ...drive reentrant calls against the parked service...
/// fetcher.release()
/// ```
public final class GatedPlaylistFetcher: PlaylistFetcherProtocol, @unchecked Sendable {
    private struct State {
        var parked: [CheckedContinuation<Void, Never>] = []
        var pendingReleases = 0
        var entryCount = 0
        var entryWaiters: [(target: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())

    /// The playlist every ``fetchPlaylist()`` call returns once released.
    public let playlist: Playlist

    public init(playlist: Playlist = .empty) {
        self.playlist = playlist
    }

    /// The number of ``fetchPlaylist()`` calls that have entered the gate.
    public var entryCount: Int {
        state.withLock { $0.entryCount }
    }

    /// Suspends until at least `count` calls have entered the gate. Returns
    /// immediately if that many already have, so it is safe to call after the
    /// fact — there is no window to lose.
    public func waitForEntry(count: Int = 1) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let satisfied = state.withLock { state -> Bool in
                if state.entryCount >= count { return true }
                state.entryWaiters.append((target: count, continuation: continuation))
                return false
            }
            if satisfied { continuation.resume() }
        }
    }

    /// Releases one parked call, or pre-authorizes the next one if none is
    /// parked yet. Pre-authorization keeps the test free of ordering
    /// constraints between `release()` and the call it releases.
    public func release() {
        let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.parked.isEmpty else {
                state.pendingReleases += 1
                return nil
            }
            return state.parked.removeFirst()
        }
        continuation?.resume()
    }

    public func fetchPlaylist() async -> Playlist {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.entryCount += 1
            let ready = state.entryWaiters.filter { $0.target <= state.entryCount }
            state.entryWaiters.removeAll { $0.target <= state.entryCount }
            return ready.map(\.continuation)
        }
        for waiter in waiters { waiter.resume() }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let preAuthorized = state.withLock { state -> Bool in
                if state.pendingReleases > 0 {
                    state.pendingReleases -= 1
                    return true
                }
                state.parked.append(continuation)
                return false
            }
            if preAuthorized { continuation.resume() }
        }

        return playlist
    }
}
