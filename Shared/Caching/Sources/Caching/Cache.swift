//
//  Cache.swift
//  Caching
//
//  Protocol defining the interface for cache implementations with TTL-based expiration.
//
//  Created by Jake Bromberg on 12/17/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Foundation

// MARK: - MetadataReadResult

/// Result of attempting to read an entry's metadata, distinguishing true absence
/// from a failed read of an intact entry.
///
/// The distinction is load-bearing for durability: an absent entry may be safely
/// (re)written or purged as legacy, while an unreadable one must be left alone —
/// treating a transient I/O or permission failure as absence would let callers
/// truncate or delete intact data. ``CacheCoordinator`` maps ``unreadable`` to
/// ``CacheCoordinator/Error/readFailed``.
public enum MetadataReadResult: Sendable {
    /// The entry exists and its metadata was decoded.
    case present(CacheMetadata)

    /// No entry (or no metadata attribute) exists — definitively absent.
    case absent

    /// The entry appears to exist but its metadata could not be read
    /// (e.g. an I/O or permission failure).
    case unreadable
}

// MARK: - Cache Protocol

/// Protocol defining the interface for cache implementations.
///
/// Conforming types provide key-value storage with metadata support for TTL-based expiration.
/// The protocol is designed to separate metadata operations from data operations, enabling
/// efficient pruning and expiration checks without loading file contents into memory.
///
/// ## Overview
///
/// Cache implementations store data alongside ``CacheMetadata`` which tracks when the entry
/// was created and how long it should live. This enables time-to-live (TTL) based expiration.
///
/// ## Thread Safety
///
/// All conforming types must be `Sendable` to support concurrent access from multiple actors.
/// The ``CacheCoordinator`` actor provides the primary thread-safe API for cache operations.
///
/// ## Implementations
///
/// - ``DiskCache``: File-based cache using extended attributes for metadata storage
/// - ``MigratingDiskCache``: Wrapper that migrates data between storage locations
public protocol Cache: Sendable {
    /// Retrieves metadata for a cached entry without loading the data.
    ///
    /// This method reads only the metadata (timestamp and lifespan) for an entry,
    /// which is useful for checking expiration status without the overhead of
    /// loading the full cached data.
    ///
    /// - Parameter key: The unique identifier for the cached entry.
    /// - Returns: The metadata if the entry exists, or `nil` if not found.
    func metadata(for key: String) -> CacheMetadata?

    /// Retrieves metadata for a cached entry, distinguishing absence from read failure.
    ///
    /// Implementations that can detect transient read failures (e.g. ``DiskCache``
    /// inspecting `errno` after `getxattr`) should return ``MetadataReadResult/unreadable``
    /// for them instead of conflating them with absence. The default implementation
    /// derives the result from ``metadata(for:)``, reporting nil as absent.
    ///
    /// - Parameter key: The unique identifier for the cached entry.
    /// - Returns: The read result for the entry's metadata.
    func metadataResult(for key: String) -> MetadataReadResult

    /// Retrieves the cached data for a key.
    ///
    /// - Parameter key: The unique identifier for the cached entry.
    /// - Returns: The cached data if found, or `nil` if the entry doesn't exist.
    func data(for key: String) -> Data?

    /// Stores data with associated metadata.
    ///
    /// If `data` is `nil`, the entry for `key` is removed from the cache.
    ///
    /// - Parameters:
    ///   - data: The data to cache, or `nil` to remove the entry.
    ///   - metadata: The metadata containing timestamp and lifespan for TTL expiration.
    ///   - key: The unique identifier for the cached entry.
    func set(_ data: Data?, metadata: CacheMetadata, for key: String)

    /// Removes an entry from the cache.
    ///
    /// - Parameter key: The unique identifier for the entry to remove.
    func remove(for key: String)

    /// Returns metadata for all cached entries.
    ///
    /// This method is used for cache pruning and key enumeration. It reads only
    /// metadata, never file contents, making it efficient for iterating over
    /// large caches.
    ///
    /// Implementations must return keys verbatim as they were stored: each
    /// returned key, passed back to ``data(for:)`` or ``metadata(for:)``, must
    /// resolve to the same entry. Callers rely on this round-trip to enumerate
    /// structured key schemes (e.g. prefix-matched day buckets).
    ///
    /// - Returns: An array of tuples containing the key and metadata for each entry.
    func allMetadata() -> [(key: String, metadata: CacheMetadata)]

    /// Removes all entries from the cache.
    ///
    /// Use this method to clear the entire cache, such as when the app version
    /// changes or the user requests a cache reset.
    func clearAll()

    /// Calculates the total storage size of all cached entries.
    ///
    /// - Returns: The total size in bytes of all cached files.
    func totalSize() -> Int64

    /// Performs periodic storage maintenance (e.g. sweeping stale temp files).
    ///
    /// Called from ``CacheCoordinator``'s asynchronous init-purge task so
    /// implementations can do directory work off the caller's actor. The
    /// default implementation is a no-op.
    func performMaintenance()
}

public extension Cache {
    /// Default implementation deriving the result from ``metadata(for:)``.
    ///
    /// **This default hard-codes nil-means-absent.** That is only correct for
    /// implementations with no transient failure mode (e.g. ``InMemoryCache``,
    /// simple test fakes). Any conformer whose reads can fail while the entry
    /// remains intact — file systems, networks, wrappers over either — MUST
    /// override this method and report ``MetadataReadResult/unreadable`` for
    /// such failures; relying on the default silently disables the
    /// `readFailed` protection and lets callers purge or truncate intact data.
    func metadataResult(for key: String) -> MetadataReadResult {
        metadata(for: key).map(MetadataReadResult.present) ?? .absent
    }

    /// Default no-op maintenance hook.
    func performMaintenance() {}
}
