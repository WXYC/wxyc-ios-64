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

    @Test("The two API versions never share a cache entry")
    func versionsGetDistinctKeys() {
        // The two versions write chronOrderIDs nine orders of magnitude apart
        // (v1: the row id, ~5.3e6; v2: the packed composite, ~8.4e15). A
        // shared entry written by a v1 session and loaded as a v2 session's
        // SSE baseline reproduces the exact stale-head bug the #839
        // invalidation was meant to kill.
        #expect(PlaylistCacheKey.playlist(for: .v1) != PlaylistCacheKey.playlist(for: .v2))
    }

    @Test("Neither key collides with the pre-#839 shared key")
    func neitherKeyIsTheLegacyKey() {
        // "com.wxyc.playlist.cache" entries hold pre-#839 id-scale keys and
        // must never be read by a post-#839 build under either version.
        #expect(PlaylistCacheKey.playlist(for: .v1) != "com.wxyc.playlist.cache")
        #expect(PlaylistCacheKey.playlist(for: .v2) != "com.wxyc.playlist.cache")
    }

    @Test("Keys are stable across calls and namespaced", arguments: PlaylistAPIVersion.allCases)
    func keysAreStableAndNamespaced(version: PlaylistAPIVersion) {
        #expect(PlaylistCacheKey.playlist(for: version) == PlaylistCacheKey.playlist(for: version))
        #expect(PlaylistCacheKey.playlist(for: version).contains("playlist"))
    }
}
