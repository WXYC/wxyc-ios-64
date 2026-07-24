//
//  PendingPlaycutLink.swift
//  WXYC
//
//  The app's "a playcut deep link is waiting to be opened" state (#434). A
//  Spotlight/Siri tap on a `PlaycutEntity` result runs `OpenPlaycut`, and a
//  tapped `wxyc://playcut/<id>` link is handled directly — both post a typed
//  `PlaycutOpenMessage`; `Singletonia` catches it and stashes this value,
//  which `RootTabView` reacts to (flipping to the Now Playing tab) and
//  `PlaylistView` consumes (scrolling its timeline to the matching row, then
//  clearing it).
//
//  `id` is already unwrapped to the underlying `UInt64` at the `Singletonia`
//  boundary — the `Playcut.id` / `PlaylistEntry.id` keyspace — so
//  `PlaylistView` never needs to import `WXYCIntents` just to compare against
//  a phantom-typed `PlaycutID`. Equatable so it can key a `.task(id:)`.
//  Mirrors `PendingConcertLink`.
//
//  Created by Jake Bromberg on 07/23/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A pending request to open a playcut, carried from the deep-link handler to
/// the Playlist timeline.
struct PendingPlaycutLink: Equatable, Sendable {
    /// The playcut id from the Spotlight/Siri result or `wxyc://playcut/<id>`
    /// link — the same `UInt64` keyspace as `Playcut.id` / `PlaylistEntry.id`.
    let id: UInt64
}
