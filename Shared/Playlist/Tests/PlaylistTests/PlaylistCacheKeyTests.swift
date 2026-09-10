//
//  PlaylistCacheKeyTests.swift
//  Playlist
//
//  Tests for PlaylistCacheKey cache key generation.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Playlist

@Suite("PlaylistCacheKey Tests")
struct PlaylistCacheKeyTests {

    /// The load-bearing assertion after the v1 path was removed (#262).
    ///
    /// A device upgrading from a v1-defaulting build (every App Store build
    /// through 3.2) still has a `com.wxyc.playlist.cache.v1` entry on disk
    /// holding rows whose `chronOrderID` is the flowsheet row id — nine orders
    /// of magnitude below the packed `(show_id, play_order)` composite this
    /// build writes. Reading that entry as a v2 session's SSE baseline
    /// reproduces the exact stale-head bug #839 was meant to kill: one live
    /// update frame later, a row from an hour ago owns the head of the
    /// timeline and the lock screen.
    ///
    /// The `.v2` suffix is what keeps that entry unreachable. It looks
    /// vestigial now that there is only one version, which is precisely why it
    /// needs a test — a tidying pass that "simplifies" the key back to a bare
    /// name walks straight into a warm v1 entry on every upgrading device.
    @Test("The key stays out of reach of entries written by a v1 build")
    func doesNotCollideWithLegacyEntries() {
        #expect(PlaylistCacheKey.playlist != "com.wxyc.playlist.cache.v1")
        // "com.wxyc.playlist.cache" entries hold pre-#839 id-scale keys and
        // must never be read by a post-#839 build either.
        #expect(PlaylistCacheKey.playlist != "com.wxyc.playlist.cache")
    }

    @Test("The key is namespaced")
    func keyIsNamespaced() {
        #expect(PlaylistCacheKey.playlist.contains("playlist"))
    }
}
