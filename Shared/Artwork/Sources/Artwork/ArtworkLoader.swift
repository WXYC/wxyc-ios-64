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

#if canImport(UIKit)
import Foundation
import UIKit
import Playlist

/// Owns per-playcut artwork loading state. Rows observe `state(for:)` rather than
/// driving fetches from their own `.task`, so cancellation of a row's view does
/// not orphan in-flight work.
///
/// Lifecycle expectations:
/// - The loader is constructed once at app launch and lives for the app's lifetime.
/// - `load(_:)` is idempotent and safe to call repeatedly; it coalesces concurrent
///   requests for the same playcut and short-circuits when state is `.loaded`.
/// - `reset(_:)` drops a single playcut's state; `retryFailures()` re-fetches every
///   `.failed` entry (used after the artwork service's fetcher chain or negative
///   cache changes); `prune(keepingKeys:)` bounds memory by dropping entries no
///   longer in the visible playlist.
@MainActor
@Observable
public final class ArtworkLoader {
    public enum State: Equatable {
        case unloaded
        case loading
        case loaded(UIImage)
        case failed

        public var isLoaded: Bool {
            if case .loaded = self { true } else { false }
        }
    }

    /// Per-key state + the Playcut that produced it. Retaining the Playcut lets
    /// `retryFailures()` re-fetch without the caller plumbing the visible-playcut
    /// list back through.
    private struct Entry {
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
    public func load(_ playcut: Playcut) {
        let key = playcut.artworkCacheKey
        switch entries[key]?.state ?? .unloaded {
        case .loaded, .loading:
            return
        case .unloaded, .failed:
            entries[key] = Entry(state: .loading, playcut: playcut)
        }

        let service = service
        Task { [weak self] in
            do {
                let cg = try await service.fetchArtwork(for: playcut)
                self?.entries[key]?.state = .loaded(cg.toUIImage())
            } catch {
                self?.entries[key]?.state = .failed
            }
        }
    }

    /// Drop a single playcut's state so the next `load(_:)` re-fetches.
    public func reset(_ playcut: Playcut) {
        entries[playcut.artworkCacheKey] = nil
    }

    /// Re-fetch every `.failed` entry using the retained Playcut. Call this after
    /// the artwork service gains a new fetcher or its negative cache is cleared,
    /// so previously-failed lookups don't have to wait for the next poll to retry.
    /// A coincident `load(_:)` coalesces because each retry transitions the entry
    /// to `.loading` before yielding.
    public func retryFailures() {
        // Snapshot before mutating, so the inner load() can rewrite entries
        // without disturbing the iteration.
        let failed = entries.values.filter { $0.state == .failed }
        for entry in failed {
            load(entry.playcut)
        }
    }

    /// Drop entries whose keys aren't in `currentKeys`. Called from
    /// `PlaylistView.task` on each playlist update to bound memory.
    public func prune(keepingKeys currentKeys: Set<String>) {
        entries = entries.filter { currentKeys.contains($0.key) }
    }
}

#endif
