//
//  MigratingDiskCache.swift
//  Caching
//
//  Cache wrapper that transparently migrates data from legacy to shared container.
//
//  Created by Jake Bromberg on 01/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Logger

// MARK: - MigratingDiskCache

/// A cache wrapper that transparently migrates data from a legacy location to a shared container.
///
/// `MigratingDiskCache` provides a seamless migration path when changing cache storage locations.
/// It wraps two ``DiskCache`` instances:
/// - **Primary**: The new shared App Group container (for widget/extension access)
/// - **Legacy**: The old private caches directory
///
/// ## Migration Behavior
///
/// The migration happens lazily on read operations:
///
/// 1. **Reads** check the primary (shared) cache first
/// 2. If not found, fall back to the legacy cache
/// 3. If found in legacy, automatically migrate to primary and delete from legacy
///
/// **Writes** always go to the primary cache only.
///
/// ## Use Case
///
/// This cache is used for playlist data that needs to be accessible from both
/// the main app and widgets. The migration allows existing cached playlists
/// to be preserved while transitioning to the shared container.
///
/// ## Thread Safety
///
/// `MigratingDiskCache` is marked `@unchecked Sendable` because both underlying
/// ``DiskCache`` instances are thread-safe.
struct MigratingDiskCache: Cache, @unchecked Sendable {
    // MARK: - Properties

    /// The primary cache in the shared App Group container.
    private let primary: any Cache

    /// The legacy cache in the app's private caches directory.
    private let legacy: any Cache

    // MARK: - Initialization

    /// Creates a migrating cache with primary (shared) and legacy (private) storage.
    init() {
        self.init(
            primary: DiskCache(useSharedContainer: true),
            legacy: DiskCache(useSharedContainer: false)
        )
    }

    /// Injection seam for tests that need to script primary/legacy failure states.
    init(primary: any Cache, legacy: any Cache) {
        self.primary = primary
        self.legacy = legacy
    }

    // MARK: - Cache Protocol Implementation

    /// Retrieves metadata, checking primary then legacy.
    ///
    /// Derives from ``metadataResult(for:)`` so both accessors apply the same
    /// no-legacy-fallback-on-unreadable policy.
    ///
    /// - Note: Does not trigger migration; use ``data(for:)`` for that.
    func metadata(for key: String) -> CacheMetadata? {
        guard case .present(let metadata) = metadataResult(for: key) else {
            return nil
        }
        return metadata
    }

    /// Classified metadata read, checking primary then legacy.
    ///
    /// A primary read failure is surfaced as ``MetadataReadResult/unreadable``
    /// rather than falling through to legacy — serving a stale legacy copy over
    /// a transiently unreadable primary would resurrect superseded data. The
    /// trade-off: a transient primary failure temporarily hides any lingering
    /// legacy copy too; that self-heals on the next successful read, which is
    /// the safe direction.
    func metadataResult(for key: String) -> MetadataReadResult {
        switch primary.metadataResult(for: key) {
        case .present(let metadata):
            .present(metadata)
        case .unreadable:
            .unreadable
        case .absent:
            legacy.metadataResult(for: key)
        }
    }

    /// Retrieves data, checking primary then legacy with automatic migration.
    ///
    /// Falls through to legacy — and destructively migrates — ONLY when the
    /// primary is definitively absent. A primary whose metadata is present (or
    /// unreadable) but whose data read fails surfaces as nil with no migration:
    /// resurrecting a stale legacy copy would overwrite the intact newer primary
    /// entry and delete the legacy original, destroying data over a transient
    /// failure. `CacheCoordinator` classifies that nil as `readFailed`.
    func data(for key: String) -> Data? {
        switch primary.metadataResult(for: key) {
        case .present:
            // The primary owns this entry; a nil read here is a transient
            // failure, never a reason to consult legacy.
            return primary.data(for: key)

        case .unreadable:
            return nil

        case .absent:
            // Fall back to legacy - migrate if found
            guard let legacyMetadata = legacy.metadata(for: key),
                  let legacyData = legacy.data(for: key) else {
                return nil
            }

            // Migrate entry from legacy to primary
            primary.set(legacyData, metadata: legacyMetadata, for: key)

            // Clean up legacy entry
            legacy.remove(for: key)
            Log(.info, category: .caching, "Migrated cache entry '\(key)' from legacy to shared container")

            return legacyData
        }
    }

    /// Stores data in the primary (shared) cache only.
    ///
    /// New writes never go to the legacy cache.
    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        primary.set(data, metadata: metadata, for: key)
    }

    /// Removes an entry from both primary and legacy caches.
    ///
    /// Cleans up both locations to ensure the entry is fully removed.
    func remove(for key: String) {
        primary.remove(for: key)
        legacy.remove(for: key)
    }

    /// Returns metadata for all entries in both caches.
    ///
    /// If an entry exists in both caches, the primary entry takes precedence.
    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        // Start with legacy entries
        var result = Dictionary(uniqueKeysWithValues: legacy.allMetadata())

        // Overwrite with primary entries (primary takes precedence)
        for (key, metadata) in primary.allMetadata() {
            result[key] = metadata
        }

        return result.map { ($0.key, $0.value) }
    }

    /// Removes all entries from both primary and legacy caches.
    func clearAll() {
        primary.clearAll()
        legacy.clearAll()
    }

    /// Returns the combined storage size of both caches.
    func totalSize() -> Int64 {
        primary.totalSize() + legacy.totalSize()
    }

    /// Forwards maintenance to both underlying caches.
    func performMaintenance() {
        primary.performMaintenance()
        legacy.performMaintenance()
    }
}
