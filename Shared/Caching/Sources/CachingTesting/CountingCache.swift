//
//  CountingCache.swift
//  CachingTesting
//
//  A call-tracking `Cache` decorator over `InMemoryCache` (#766). Replaces two
//  hand-rolled ~50-line mock caches in Shared/Metadata/Tests/MetadataTests that
//  reimplemented the full `Cache` protocol with call-tracking bolted on.
//
//  Created by Jake Bromberg on 08/05/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Caching
import Foundation

/// Wraps an `InMemoryCache`, tallying `metadata(for:)`/`set(_:metadata:for:)`
/// calls and the keys involved, so tests can assert on cache-hit/miss behavior
/// without reimplementing storage.
public final class CountingCache: Cache, @unchecked Sendable {
    private let inner: InMemoryCache
    private let lock = NSLock()
    private var _accessedKeys: [String] = []
    private var _setKeys: [String] = []

    public init(inner: InMemoryCache = InMemoryCache()) {
        self.inner = inner
    }

    /// Keys passed to `metadata(for:)`, in call order (including misses).
    public var accessedKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _accessedKeys
    }

    /// Keys passed to `set(_:metadata:for:)`, in call order.
    public var setKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _setKeys
    }

    /// The number of `metadata(for:)` calls. Equivalent to `accessedKeys.count`.
    public var getCallCount: Int { accessedKeys.count }

    /// The number of `set(_:metadata:for:)` calls. Equivalent to `setKeys.count`.
    public var setCallCount: Int { setKeys.count }

    public func metadata(for key: String) -> CacheMetadata? {
        lock.lock()
        _accessedKeys.append(key)
        lock.unlock()
        return inner.metadata(for: key)
    }

    public func data(for key: String) -> Data? {
        inner.data(for: key)
    }

    public func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        lock.lock()
        _setKeys.append(key)
        lock.unlock()
        inner.set(data, metadata: metadata, for: key)
    }

    public func remove(for key: String) {
        inner.remove(for: key)
    }

    public func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        inner.allMetadata()
    }

    public func clearAll() {
        inner.clearAll()
    }

    public func totalSize() -> Int64 {
        inner.totalSize()
    }

    /// Clears the call tallies. The wrapped cache's stored data is untouched —
    /// use `clearAll()` to reset storage too.
    public func reset() {
        lock.lock()
        _accessedKeys.removeAll()
        _setKeys.removeAll()
        lock.unlock()
    }
}
