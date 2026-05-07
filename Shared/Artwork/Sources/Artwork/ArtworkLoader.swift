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
/// - `reset(_:)` drops a single playcut's state; `resetFailures()` resets only
///   `.failed` entries (used after the artwork service's fetcher chain or negative
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
    }

    public private(set) var states: [String: State] = [:]
    private let service: any ArtworkService

    public init(service: any ArtworkService) {
        self.service = service
    }

    public func state(for playcut: Playcut) -> State {
        states[playcut.artworkCacheKey] ?? .unloaded
    }

    /// Schedule a fetch for `playcut`. No-op when already `.loaded` or `.loading`.
    /// Transitions `.unloaded`/`.failed` -> `.loading` -> `.loaded`/`.failed`.
    public func load(_ playcut: Playcut) {
        let key = playcut.artworkCacheKey
        switch states[key] ?? .unloaded {
        case .loaded, .loading:
            return
        case .unloaded, .failed:
            states[key] = .loading
        }

        let service = service
        Task { [weak self] in
            do {
                let cg = try await service.fetchArtwork(for: playcut)
                self?.states[key] = .loaded(cg.toUIImage())
            } catch {
                self?.states[key] = .failed
            }
        }
    }

    /// Drop a single playcut's state so the next `load(_:)` re-fetches.
    public func reset(_ playcut: Playcut) {
        states[playcut.artworkCacheKey] = .unloaded
    }

    /// Reset every `.failed` entry to `.unloaded`. Use after the artwork service
    /// gains a new fetcher or its negative cache is cleared, so subsequent
    /// `load(_:)` calls re-attempt those playcuts.
    public func resetFailures() {
        for (key, state) in states where state == .failed {
            states[key] = .unloaded
        }
    }

    /// Drop entries whose keys aren't in `currentKeys`. Called from
    /// `PlaylistView.task` on each playlist update to bound memory.
    public func prune(keepingKeys currentKeys: Set<String>) {
        states = states.filter { currentKeys.contains($0.key) }
    }
}

#endif
