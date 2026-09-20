//
//  ArtworkLoader.swift
//  Artwork
//
//  Observable, MainActor-isolated repository for per-playcut artwork loading state.
//  Decouples artwork fetches from view lifecycle so that LazyVStack eviction,
//  transition animations, and other view churn don't lose in-flight work.
//
//  Created by Jake Bromberg on 05/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import CoreGraphics
import Core
import Playlist

/// Owns per-playcut artwork loading state. Rows observe `state(for:)` rather than
/// driving fetches from their own `.task`, so cancellation of a row's view does
/// not orphan in-flight work.
///
/// Lifecycle expectations:
/// - The loader is constructed once at app launch and lives for the app's lifetime.
/// - `load(_:)` is idempotent and safe to call repeatedly; it coalesces concurrent
///   requests for the same playcut and short-circuits when state is `.loaded`.
/// - `retryFailures()` re-fetches every `.failed` entry (for when the negative
///   cache changes out from under the loader; currently caller-less — see #293);
///   `prune(keepingKeys:)` bounds memory by dropping entries no longer in the
///   visible playlist.
@MainActor
@Observable
public final class ArtworkLoader {
    public enum State: Equatable {
        case unloaded
        case loading
        case loaded(Core.Image)
        case failed
        /// The MD has flagged this release "Not on Discogs" (#390), so the
        /// loader never attempted a fetch. Distinct from `.failed` — this is
        /// a deliberate suppression, not a lookup that came back empty, so
        /// `retryFailures()` must not touch it (retrying would be pointless
        /// and could churn the state on a coincidentally-resolvable stale
        /// URL). Carries the optional MD note so a view with room to show it
        /// can.
        case notOnDiscogs(note: String?)

        public var isLoaded: Bool {
            if case .loaded = self { true } else { false }
        }
    }

    /// Per-key state + the Playcut that produced it. Retaining the Playcut lets
    /// `retryFailures()` re-fetch without the caller plumbing the visible-playcut
    /// list back through.
    ///
    /// Internal rather than private so `LoaderTransition` (a separate file) can
    /// operate on it as plain data.
    struct Entry: Equatable {
        var state: State
        let playcut: Playcut
    }

    private var entries: [String: Entry] = [:]
    private let service: any ArtworkService

    public init(service: any ArtworkService) {
        self.service = service
    }

    public func state(for playcut: Playcut) -> State {
        entries[playcut.artworkCacheKey]?.state ?? .unloaded
    }

    /// Schedule a fetch for `playcut`. No-op when already `.loaded` or `.loading`.
    /// Transitions `.unloaded`/`.failed` -> `.loading` -> `.loaded`/`.failed`.
    ///
    /// Short-circuits to `.notOnDiscogs` without ever calling `service` when
    /// `playcut.discogsUnavailable == true` (#390) — suppressing the fetch
    /// entirely, not just its result, since the MD flag means any resolvable
    /// artwork URL is a preserved false match the flag exists to stop
    /// rendering.
    public func load(_ playcut: Playcut) {
        dispatch(.load(playcut))
    }

    /// Drop a single playcut's state so the next `load(_:)` re-fetches.
    ///
    /// Deliberately `internal` rather than `public`: nothing outside this module
    /// calls it. `retryFailures()` and `prune(keepingKeys:)` cover the two live
    /// use cases (fetcher-chain upgrade, playlist scroll eviction). It is kept
    /// rather than deleted because it is the only primitive that drops exactly
    /// one entry — `prune(keepingKeys:)` takes a keep-set a caller cannot build,
    /// since `entries` is private, and `retryFailures()` only touches `.failed`.
    /// Coverage is asymmetric, so be precise about it: `LoaderEvent.reset` — the
    /// state-machine case this dispatches — is covered by `LoaderTransitionTests`,
    /// which is ungated and runs on the host and in CI. This wrapper's own test,
    /// `resetClearsLoadedEntry`, is developer-only: its file is entirely inside
    /// `#if canImport(UIKit)` so it vanishes from a host `swift test`, and on the
    /// simulator its suite is `.ciHang`-disabled, which CI sets. Treat a local
    /// simulator run as the only thing that exercises this method.
    ///
    /// Promote back to `public` when a caller (e.g. a per-row "force refresh
    /// artwork" action) actually appears.
    func reset(_ playcut: Playcut) {
        dispatch(.reset(key: playcut.artworkCacheKey))
    }

    /// Re-fetch every `.failed` entry using the retained Playcut. Call this when
    /// the artwork service's negative cache has been cleared out from under the
    /// loader, so previously-failed lookups don't wait for the next poll to retry.
    /// A coincident `load(_:)` coalesces because each retry transitions the entry
    /// to `.loading` before yielding.
    public func retryFailures() {
        dispatch(.retryFailures)
    }

    /// Drop entries whose keys aren't in `currentKeys`. Called from
    /// `PlaylistView.task` on each playlist update to bound memory.
    public func prune(keepingKeys currentKeys: Set<String>) {
        dispatch(.prune(keepingKeys: currentKeys))
    }

    // MARK: - Private

    /// Runs `event` through the pure `LoaderTransition`, applies the resulting
    /// state, then executes any effects it returned.
    private func dispatch(_ event: LoaderEvent) {
        let (next, effects) = LoaderTransition.apply(event, to: entries)
        entries = next
        for effect in effects {
            run(effect)
        }
    }

    /// Performs a side effect returned by `LoaderTransition.apply`. This is the
    /// only place `ArtworkLoader` touches the network/service layer or spawns a
    /// `Task` — everything else is a pure dictionary transformation.
    private func run(_ effect: LoaderEffect) {
        switch effect {
        case .startFetch(let playcut):
            let key = playcut.artworkCacheKey
            let service = service
            Task { [weak self] in
                do {
                    let cg = try await service.fetchArtwork(for: playcut)
                    self?.dispatch(.fetchSucceeded(key: key, image: cg.toImage()))
                } catch {
                    self?.dispatch(.fetchFailed(key: key))
                }
            }
        }
    }
}
