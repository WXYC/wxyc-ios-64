import Foundation
import Logger

/// A cache that migrates data from a legacy private location to a shared App Group container.
/// On reads: checks shared container first, falls back to legacy, auto-migrates if found in legacy.
/// On writes: always writes to shared container only.
struct MigratingDiskCache: Cache, @unchecked Sendable {
    private let primary: DiskCache      // Shared container
    private let legacy: DiskCache       // Private caches dir

    init() {
        self.primary = DiskCache(useSharedContainer: true)
        self.legacy = DiskCache(useSharedContainer: false)
    }

    func metadata(for key: String) -> CacheMetadata? {
        // Check primary first
        if let metadata = primary.metadata(for: key) {
            return metadata
        }
        // Fall back to legacy
        return legacy.metadata(for: key)
    }

    func data(for key: String) -> Data? {
        // Check primary first
        if let data = primary.data(for: key) {
            return data
        }
        // Fall back to legacy, migrate if found
        guard let legacyMetadata = legacy.metadata(for: key),
              let legacyData = legacy.data(for: key) else {
            return nil
        }
        // Migrate to primary
        primary.set(legacyData, metadata: legacyMetadata, for: key)
        // Clean up legacy
        legacy.remove(for: key)
        Log(.info, "Migrated cache entry '\(key)' from legacy to shared container")
        return legacyData
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        // Always write to primary (shared container)
        primary.set(data, metadata: metadata, for: key)
    }

    func remove(for key: String) {
        primary.remove(for: key)
        legacy.remove(for: key)  // Clean up both locations
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        // Combine both, preferring primary
        var result = Dictionary(uniqueKeysWithValues: legacy.allMetadata())
        for (key, metadata) in primary.allMetadata() {
            result[key] = metadata  // Primary overwrites legacy
        }
        return result.map { ($0.key, $0.value) }
    }
}
