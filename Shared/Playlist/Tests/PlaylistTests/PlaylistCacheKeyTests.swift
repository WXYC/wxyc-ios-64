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

    @Test("playlist key returns consistent value")
    func playlistKeyReturnsConsistentValue() {
        let key1 = PlaylistCacheKey.playlist
        let key2 = PlaylistCacheKey.playlist
        #expect(key1 == key2)
    }

    @Test("playlist key uses namespaced format")
    func playlistKeyUsesNamespacedFormat() {
        let key = PlaylistCacheKey.playlist
        #expect(key.contains("playlist"))
    }
}
