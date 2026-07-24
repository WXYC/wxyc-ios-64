//
//  PlaycutOpenRouter.swift
//  WXYC
//
//  Pure resolution logic for a pending playcut deep link (#434): given the
//  currently loaded playlist timeline, decides which row `PlaylistView`
//  should scroll to. Factored out of the view so the message → scroll
//  mapping is unit-testable without SwiftUI or a live `PlaylistService`.
//
//  A miss (the target playcut isn't in the visible ~50-entry window — either
//  not yet loaded, or older than the client's rolling history) resolves to
//  `nil`; `PlaylistView` treats that as a silent no-op rather than an error
//  UI, matching this ticket's scope (see docs/ideas/spotlight-app-entities.md,
//  C1 — no "couldn't find that row" affordance was requested).
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist

enum PlaycutOpenRouter {
    /// The row id `PlaylistView`'s `ScrollViewReader` should scroll to for
    /// `link`, or `nil` if the target playcut isn't among `entries`.
    ///
    /// Matches only `Playcut` entries — `PlaylistEntry.id` is a shared
    /// keyspace across playcuts, breakpoints, talksets, and show markers, so
    /// this deliberately doesn't scroll to a non-playcut entry that happens
    /// to share the numeric id.
    static func scrollTarget(for link: PendingPlaycutLink, in entries: [any PlaylistEntry]) -> UInt64? {
        entries.contains { ($0 as? Playcut)?.id == link.id } ? link.id : nil
    }
}
