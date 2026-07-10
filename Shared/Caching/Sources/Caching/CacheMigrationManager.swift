//
//  CacheMigrationManager.swift
//  Caching
//
//  Manages cache invalidation when app version changes to prevent stale data issues.
//
//  Created by Jake Bromberg on 12/04/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation
import Logger

// MARK: - CacheMigrationManager

/// Manages cache invalidation when the app version changes.
///
/// `CacheMigrationManager` detects when the app's marketing version has changed
/// and automatically purges DiskCache-owned entries under the caches roots to
/// prevent stale or incompatible data from causing issues after updates.
///
/// ## Why Version-Based Cache Invalidation?
///
/// Cache formats may change between app versions. Attempting to read data cached
/// by an older version could cause crashes or incorrect behavior. By purging
/// caches on version change, we ensure a clean slate for the new version.
///
/// ## Usage
///
/// Call ``migrateIfNeeded()`` early in the app launch sequence:
///
/// ```swift
/// @main
/// struct WXYCApp: App {
///     init() {
///         CacheMigrationManager.migrateIfNeeded()
///         // ... other initialization
///     }
/// }
/// ```
///
/// ## Storage Locations
///
/// This manager purges DiskCache entries (identified by their metadata xattr) in:
/// - The app's private caches directory (`~/Library/Caches`)
/// - The shared App Group container caches (`group.wxyc.iphone/Library/Caches`)
///
/// **Application Support stores are deliberately exempt.** Data lives there
/// precisely because it is irreplaceable — a purge on every marketing-version
/// bump would routinely destroy locally-accreted data that cannot be
/// re-fetched. Schema drift in such data must instead be absorbed by tolerant
/// decoders on the stored types and by `CacheCoordinator`'s corrupt-entry
/// eviction.
public enum CacheMigrationManager {
    // MARK: - Private Constants

    /// UserDefaults key for tracking the last known app version.
    private static let lastKnownVersionKey = "CacheMigrationManager.lastKnownVersion"

    /// UserDefaults key for tracking the cache schema version.
    private static let schemaVersionKey = "CacheMigrationManager.schemaVersion"

    /// Increment this when any cached Codable type changes shape (added/removed/renamed fields).
    /// This triggers a cache purge independently of the app's marketing version, catching
    /// within-version schema drift (e.g., a build increment that changes a cached struct).
    ///
    /// Note: this does NOT protect Application Support data — those stores are
    /// exempt from purges, and their defense against schema drift is a tolerant
    /// decoder on the stored type plus `CacheCoordinator`'s corrupt-entry eviction.
    static let cacheSchemaVersion: Int = 1

    /// The App Group identifier for the shared container.
    private static let appGroupID = "group.wxyc.iphone"

    // MARK: - Public API

    /// Checks if the app version has changed and purges caches if needed.
    ///
    /// Call this method early in the app launch sequence, before accessing
    /// any cached data. If the marketing version has changed since the last
    /// launch, all caches are cleared and the new version is recorded.
    ///
    /// - Note: This method uses ``UserDefaults/wxyc`` (the shared App Group
    ///   UserDefaults) to persist the version across launches.
    public static func migrateIfNeeded() {
        let currentVersion = Bundle.main.marketingVersion
        let lastKnownVersion = UserDefaults.wxyc.string(forKey: lastKnownVersionKey)
        let lastKnownSchema = UserDefaults.wxyc.integer(forKey: schemaVersionKey)

        // Check if version or schema has changed since last launch
        if lastKnownVersion != currentVersion || lastKnownSchema != cacheSchemaVersion {
            Log(.info, category: .caching, "Cache invalidated — version: \(lastKnownVersion ?? "nil") → \(currentVersion), schema: \(lastKnownSchema) → \(cacheSchemaVersion). Purging cache.")
            purgeAllCaches()
            // Record the new version and schema to prevent re-purging on next launch
            UserDefaults.wxyc.set(currentVersion, forKey: lastKnownVersionKey)
            UserDefaults.wxyc.set(cacheSchemaVersion, forKey: schemaVersionKey)
        }
    }

    // MARK: - Private Methods

    /// Removes all files from both the private and shared cache directories.
    private static func purgeAllCaches() {
        // Clear the app's private cache directory
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            purgeFiles(in: cacheDir)
        }

        // Clear the shared App Group container's cache directory
        if let sharedCacheDir = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Library/Caches", isDirectory: true) {
            purgeFiles(in: sharedCacheDir)
        }
    }

    /// Removes cache files from `directory`, preserving directory nodes, foreign
    /// subdirectory contents, and in-flight temp files.
    ///
    /// Three scoping rules, all load-bearing:
    /// - **The root's top level is cleared outright** (tagged or not): it has
    ///   been WXYC-owned for years, and pre-xattr-era cache files there would
    ///   otherwise become permanent cruft — never purged, skipped by
    ///   `totalSize()`/`clearAll()`, their keys never re-read.
    /// - **Recursion into subdirectories deletes only files bearing the DiskCache
    ///   metadata xattr.** Subdirectories are where foreign subsystems park —
    ///   Sentry's `io.sentry` envelope queue (holding crash reports from the
    ///   just-replaced version, not yet uploaded at this point in launch) and
    ///   NSURLCache's `Cache.db` among them. Ownership is proven per-file by the
    ///   xattr, the same discipline `DiskCache.clearAll()` uses.
    /// - **In-flight temp files are never touched.** Temps carry the ownership
    ///   xattr before their rename; deleting one makes another process's rename
    ///   fail and loses that write. The coordinator's maintenance sweep owns
    ///   stale-temp cleanup.
    ///
    /// Directory nodes are preserved throughout: `DiskCache(subdirectory:)`
    /// instances hold the URL of their subdirectory, and deleting the node would
    /// leave them pointing at a path that no longer exists.
    static func purgeFiles(in directory: URL) {
        purgeFiles(in: directory, isPurgeRoot: true)
    }

    private static func purgeFiles(in directory: URL, isPurgeRoot: Bool) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            return
        }

        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?
                .isDirectory ?? false
            if isDirectory {
                purgeFiles(in: url, isPurgeRoot: false)
            } else if DiskCache.isTempFile(url) {
                continue
            } else if isPurgeRoot || DiskCache.hasCacheMetadata(at: url) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

// MARK: - Bundle Extension

private extension Bundle {
    /// The app's marketing version (e.g., "1.2.3") from Info.plist.
    ///
    /// Falls back to "0.0.0" if the version string is not available.
    var marketingVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
