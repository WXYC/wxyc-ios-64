//
//  InMemoryCache.swift
//  Caching
//
//  Thread-safe in-memory Cache implementation for isolated test execution.
//  Use in tests to avoid file system dependencies and enable parallel test runs.
//
//  Created by Jake Bromberg on 03/29/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// Thread-safe in-memory implementation of the ``Cache`` protocol for testing.
///
/// Use this instead of ``DiskCache`` in tests to avoid file system dependencies
/// and enable parallel test execution without interference. Each test can create
/// its own instance, just like ``InMemoryDefaults``.
///
/// ## Usage
///
/// ```swift
/// let cache = InMemoryCache()
/// let coordinator = CacheCoordinator(cache: cache)
/// ```
public final class InMemoryCache: Cache, @unchecked Sendable {
    private var dataStorage: [String: Data] = [:]
    private var metadataStorage: [String: CacheMetadata] = [:]
    private let lock = NSLock()

    public init() {}

    public func metadata(for key: String) -> CacheMetadata? {
        lock.lock()
        defer { lock.unlock() }
        return metadataStorage[key]
    }

    public func data(for key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return dataStorage[key]
    }

    public func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let data {
            dataStorage[key] = data
            metadataStorage[key] = metadata
        } else {
            _remove(for: key)
        }
    }

    public func remove(for key: String) {
        lock.lock()
        defer { lock.unlock() }
        _remove(for: key)
    }

    public func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        lock.lock()
        defer { lock.unlock() }
        return metadataStorage.map { ($0.key, $0.value) }
    }

    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        dataStorage.removeAll()
        metadataStorage.removeAll()
    }

    public func totalSize() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return dataStorage.values.reduce(0) { $0 + Int64($1.count) }
    }

    // MARK: - Private

    private func _remove(for key: String) {
        dataStorage.removeValue(forKey: key)
        metadataStorage.removeValue(forKey: key)
    }
}
