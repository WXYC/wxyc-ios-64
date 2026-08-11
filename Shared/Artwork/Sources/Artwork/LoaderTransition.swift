//
//  LoaderTransition.swift
//  Artwork
//
//  Pure state-transition function for ArtworkLoader's per-playcut state
//  machine (#298). `LoaderTransition.apply(_:to:)` maps the current entries
//  and an event to the next entries plus any side effects the caller should
//  run — no I/O, no clock, no globals, no actor isolation. `ArtworkLoader`
//  is the thin `@MainActor` shell that owns `entries`, dispatches events
//  here, and executes the returned effects.
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Playlist

/// Inputs that can change `ArtworkLoader`'s per-playcut state.
enum LoaderEvent: Equatable {
    /// Request a fetch for `playcut`. No-op when the entry is already
    /// `.loaded` or `.loading`. Short-circuits to `.notOnDiscogs` without a
    /// `.startFetch` effect when `playcut.discogsUnavailable == true` (#390).
    case load(Playcut)
    /// A fetch for `key` completed with `image`. A no-op unless the entry is
    /// currently `.loading` — guards the case where the fetch that produced
    /// this result was superseded by a `.reset`/`.prune` (and possibly a
    /// fresh `.load`) before it finished.
    case fetchSucceeded(key: String, image: Core.Image)
    /// A fetch for `key` failed. Same `.loading`-only guard as `fetchSucceeded`.
    case fetchFailed(key: String)
    /// Drop a single playcut's state so the next `.load` re-fetches.
    case reset(key: String)
    /// Re-fetch every entry currently `.failed`, using its retained Playcut.
    case retryFailures
    /// Drop entries whose keys aren't in `keepingKeys`.
    case prune(keepingKeys: Set<String>)
}

/// A side effect `ArtworkLoader` must run in response to an event. Kept as
/// data — rather than performed inline — so `LoaderTransition.apply` stays
/// pure and every branch is testable without an actor or a fake service.
enum LoaderEffect: Equatable, Hashable {
    /// Start an async fetch for `playcut`; the caller is responsible for
    /// feeding the result back in as `.fetchSucceeded`/`.fetchFailed`.
    case startFetch(Playcut)
}

/// Pure per-key state machine for `ArtworkLoader`. No I/O, no clock, no
/// globals — every branch is a deterministic function of its inputs.
enum LoaderTransition {
    static func apply(
        _ event: LoaderEvent,
        to entries: [String: ArtworkLoader.Entry]
    ) -> (next: [String: ArtworkLoader.Entry], effects: [LoaderEffect]) {
        var entries = entries
        var effects: [LoaderEffect] = []

        switch event {
        case .load(let playcut):
            let key = playcut.artworkCacheKey

            if playcut.discogsUnavailable == true {
                if case .notOnDiscogs = entries[key]?.state {
                    break
                }
                entries[key] = ArtworkLoader.Entry(
                    state: .notOnDiscogs(note: playcut.discogsUnavailableNote),
                    playcut: playcut
                )
                break
            }

            switch entries[key]?.state ?? .unloaded {
            case .loaded, .loading:
                break
            case .unloaded, .failed, .notOnDiscogs:
                entries[key] = ArtworkLoader.Entry(state: .loading, playcut: playcut)
                effects.append(.startFetch(playcut))
            }

        case .fetchSucceeded(let key, let image):
            if entries[key]?.state == .loading {
                entries[key]?.state = .loaded(image)
            }

        case .fetchFailed(let key):
            if entries[key]?.state == .loading {
                entries[key]?.state = .failed
            }

        case .reset(let key):
            entries[key] = nil

        case .retryFailures:
            // Snapshot the failed set before recursing, so mutations made by
            // one retry's `.load` don't perturb the set we're iterating.
            let failedPlaycuts = entries.values.filter { $0.state == .failed }.map(\.playcut)
            for playcut in failedPlaycuts {
                let result = apply(.load(playcut), to: entries)
                entries = result.next
                effects.append(contentsOf: result.effects)
            }

        case .prune(let keepingKeys):
            entries = entries.filter { keepingKeys.contains($0.key) }
        }

        return (entries, effects)
    }
}
