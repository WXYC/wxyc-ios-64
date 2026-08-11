//
//  CountingCacheTests.swift
//  CachingTests
//
//  Tests for the `CountingCache` decorator (#766): it must forward every
//  `Cache` operation to its wrapped `InMemoryCache` unchanged while tallying
//  `metadata(for:)`/`set(_:metadata:for:)` calls and the keys involved, and
//  `reset()` must clear the tallies without touching the wrapped storage.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
import Foundation
@testable import Caching
import CachingTesting

@Suite("CountingCache Tests")
struct CountingCacheTests {

    @Test("metadata(for:) is forwarded and tallied")
    func metadataIsForwardedAndTallied() {
        let cache = CountingCache()
        let metadata = CacheMetadata(lifespan: 3600)
        cache.set(Data("la paradoja".utf8), metadata: metadata, for: "juana-molina")

        let result = cache.metadata(for: "juana-molina")

        #expect(result?.lifespan == 3600)
        #expect(cache.getCallCount == 1)
        #expect(cache.accessedKeys == ["juana-molina"])
    }

    @Test("set(_:metadata:for:) is forwarded and tallied")
    func setIsForwardedAndTallied() {
        let cache = CountingCache()
        let metadata = CacheMetadata(lifespan: 3600)

        cache.set(Data("Aluminum Tunes".utf8), metadata: metadata, for: "stereolab")

        #expect(cache.data(for: "stereolab") == Data("Aluminum Tunes".utf8))
        #expect(cache.setCallCount == 1)
        #expect(cache.setKeys == ["stereolab"])
    }

    @Test("A miss is tallied like a hit — accessedKeys records every metadata(for:) call")
    func missIsStillTallied() {
        let cache = CountingCache()

        let result = cache.metadata(for: "missing-key")

        #expect(result == nil)
        #expect(cache.getCallCount == 1)
        #expect(cache.accessedKeys == ["missing-key"])
    }

    @Test("reset() clears the tallies without touching stored data")
    func resetClearsTalliesOnly() {
        let cache = CountingCache()
        let metadata = CacheMetadata(lifespan: 3600)
        cache.set(Data("Moon Pix".utf8), metadata: metadata, for: "cat-power")
        _ = cache.metadata(for: "cat-power")

        cache.reset()

        #expect(cache.getCallCount == 0)
        #expect(cache.setCallCount == 0)
        #expect(cache.accessedKeys.isEmpty)
        #expect(cache.setKeys.isEmpty)
        // The underlying entry survives the reset — only the tallies clear.
        #expect(cache.data(for: "cat-power") == Data("Moon Pix".utf8))
    }

    @Test("Concurrent access tallies every call exactly once")
    func concurrentAccessIsRaceFree() async {
        // `CountingCache` is `@unchecked Sendable`, so the tallies have to be
        // genuinely lock-guarded rather than merely asserted to be safe — an
        // unsynchronized `[String]` append from many tasks loses writes and
        // corrupts the buffer. Concurrent metadata/set traffic is realistic:
        // CacheCoordinator fans out per-key work.
        let cache = CountingCache()
        let metadata = CacheMetadata(lifespan: 3600)
        let iterations = 200

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    cache.set(Data("v\(i)".utf8), metadata: metadata, for: "key-\(i)")
                    _ = cache.metadata(for: "key-\(i)")
                }
            }
        }

        #expect(cache.setCallCount == iterations)
        #expect(cache.getCallCount == iterations)
        #expect(Set(cache.setKeys).count == iterations)
        #expect(Set(cache.accessedKeys).count == iterations)
    }

    @Test("remove(for:), clearAll(), allMetadata(), and totalSize() delegate to the inner cache")
    func passthroughOperationsDelegate() {
        let cache = CountingCache()
        let metadata = CacheMetadata(lifespan: 3600)
        cache.set(Data("Back, Baby".utf8), metadata: metadata, for: "jessica-pratt")

        #expect(cache.allMetadata().map(\.key) == ["jessica-pratt"])
        #expect(cache.totalSize() == Int64("Back, Baby".utf8.count))

        cache.remove(for: "jessica-pratt")
        #expect(cache.data(for: "jessica-pratt") == nil)

        cache.set(Data("la paradoja".utf8), metadata: metadata, for: "juana-molina")
        cache.clearAll()
        #expect(cache.allMetadata().isEmpty)
    }
}
