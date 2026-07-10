//
//  DiskCache.swift
//  Caching
//
//  File-based cache using extended attributes (xattr) for metadata storage.
//
//  Created by Jake Bromberg on 12/17/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Core
import Foundation
import Logger

// MARK: - DiskCache

/// File-based cache implementation using extended attributes for metadata.
///
/// `DiskCache` stores cached data as files on disk, with ``CacheMetadata`` stored
/// as a file extended attribute (`xattr`). This approach keeps metadata close to
/// the data without requiring separate metadata files.
///
/// ## Storage Locations
///
/// `DiskCache` supports three storage locations:
/// - **Private**: The app's caches directory (`~/Library/Caches`)
/// - **Shared**: The App Group container (`group.wxyc.iphone/Library/Caches`)
/// - **Application Support**: A named subdirectory of the app's Application
///   Support directory — never purged by the system and included in backups,
///   the home of irreplaceable, locally-accreted data
///
/// Use the shared container when data needs to be accessible from widgets
/// or extensions.
///
/// ## Extended Attributes
///
/// Metadata is stored using the POSIX `xattr` API with the attribute name
/// `com.wxyc.cache.metadata`. This approach:
/// - Keeps metadata atomically attached to files
/// - Survives file moves within the same filesystem
/// - Is automatically cleaned up when files are deleted
///
/// ## Thread Safety
///
/// `DiskCache` is marked `@unchecked Sendable` because file operations are
/// inherently thread-safe on APFS/HFS+ at the file level. The internal
/// `NSCache` is also thread-safe.
///
/// ## Legacy File Handling
///
/// Files without the metadata extended attribute are considered legacy entries
/// from older cache formats and are automatically purged when accessed.
struct DiskCache: Cache, @unchecked Sendable {
    // MARK: - Storage Location

    /// Where a private (non-App-Group) cache stores its files.
    enum StorageLocation: Sendable {
        /// The app's caches directory (`~/Library/Caches`). The system may purge
        /// this location under disk pressure — use it for re-fetchable data.
        case caches

        /// A named subdirectory of the app's Application Support directory. Never
        /// purged by the system and included in backups — use it for irreplaceable,
        /// locally-accreted data that cannot be re-created after a device restore.
        ///
        /// The subdirectory is required (and must be non-empty) so a cache can
        /// never root itself — nor point the legacy purge — at the Application
        /// Support root, which other subsystems (e.g. PostHog) share.
        case applicationSupport(subdirectory: String)
    }

    // MARK: - Error Type

    /// Error type for disk cache operations.
    ///
    /// Conforms to `ExpressibleByStringLiteral` for convenient error creation
    /// in logging contexts.
    struct DiskCacheError: LocalizedError, ExpressibleByStringLiteral, CustomStringConvertible {
        let message: String

        var description: String { message }
        var errorDescription: String? { message }

        init(stringLiteral value: String) {
            self.message = value
        }
    }

    // MARK: - Constants

    /// The extended attribute name used to store cache metadata.
    private static let metadataAttributeName = "com.wxyc.cache.metadata"

    /// The App Group identifier for the shared container.
    private static let appGroupID = "group.wxyc.iphone"

    // MARK: - Properties

    /// In-memory cache used as fallback when disk storage is unavailable.
    private let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
        cache.countLimit = 500
        return cache
    }()

    /// The directory where cache files are stored, or `nil` if unavailable.
    private let cacheDirectory: URL?

    /// Whether `cacheDirectory` is a subdirectory this cache owns exclusively.
    ///
    /// Root-scoped caches (the private caches root, the shared container root)
    /// share their directory with other subsystems, so maintenance there must
    /// prove per-file ownership; subdirectory-scoped caches may act on any file.
    private let ownsCacheDirectoryExclusively: Bool

    // MARK: - Initialization

    /// Creates a disk cache with the specified storage location.
    ///
    /// - Parameters:
    ///   - useSharedContainer: If `true`, uses the App Group shared container
    ///     for storage, enabling access from widgets and extensions. If `false`, uses
    ///     the private location selected by `location`.
    ///   - subdirectory: Optional subdirectory name to isolate this cache's files
    ///     when `location` is ``StorageLocation/caches``. For Application Support
    ///     the subdirectory travels in the enum case instead.
    ///   - location: Which private directory to root the cache in when
    ///     `useSharedContainer` is `false`. Defaults to ``StorageLocation/caches``;
    ///     use ``StorageLocation/applicationSupport(subdirectory:)`` for
    ///     irreplaceable data. The Application Support subdirectory is created on
    ///     demand and remains included in backups.
    ///
    /// - Note: On the simulator, the shared container may not be available. In this
    ///   case, the cache falls back to in-memory storage without logging an error.
    init(useSharedContainer: Bool = false, subdirectory: String? = nil, location: StorageLocation = .caches) {
        // Use the selected private directory if shared container not requested
        guard useSharedContainer else {
            switch location {
            case .caches:
                var dir = FileManager.default.urls(
                    for: .cachesDirectory,
                    in: .userDomainMask
                ).first
                if let subdirectory, let base = dir {
                    let scoped = base.appending(path: subdirectory)
                    try? FileManager.default.createDirectory(at: scoped, withIntermediateDirectories: true)
                    dir = scoped
                }
                self.cacheDirectory = dir
                self.ownsCacheDirectoryExclusively = subdirectory != nil

            case .applicationSupport(let requiredSubdirectory):
                precondition(!requiredSubdirectory.isEmpty,
                             "applicationSupport requires a non-empty subdirectory")
                precondition(subdirectory == nil,
                             "Pass the Application Support subdirectory via the location case")
                // Application Support may not exist on a fresh install.
                if var scoped = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                ).first?.appending(path: requiredSubdirectory) {
                    try? FileManager.default.createDirectory(at: scoped, withIntermediateDirectories: true)
                    // Affirmatively INCLUDE in backups: the data here is
                    // irreplaceable, and directories created by earlier builds
                    // may carry a persisted exclusion flag that must be cleared.
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = false
                    try? scoped.setResourceValues(resourceValues)
                    self.cacheDirectory = scoped
                } else {
                    self.cacheDirectory = nil
                }
                self.ownsCacheDirectoryExclusively = true
            }

            return
        }

        // Attempt to use the App Group shared container
        if let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
        {
            // Build the path to Library/Caches within the shared container
            let cacheDir = container
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)

            // Create the directory if it doesn't exist
            try? FileManager.default.createDirectory(
                at: cacheDir,
                withIntermediateDirectories: true
            )

            self.cacheDirectory = cacheDir
            self.ownsCacheDirectoryExclusively = false
        } else {
            // Shared container unavailable - log error (except on simulator)
            #if !targetEnvironment(simulator)
            Log(.error, category: .caching, "App group container not available for '\(Self.appGroupID)'. Check entitlements and provisioning profile.")
            #endif
            self.cacheDirectory = nil
            self.ownsCacheDirectoryExclusively = false
        }
    }

    // MARK: - Extended Attribute Helpers

    /// Result of reading the metadata extended attribute from a file.
    ///
    /// The four cases drive different handling: `present` serves the entry,
    /// `absent` and `corrupt` justify a destructive legacy purge (the attribute
    /// definitively doesn't exist, or exists but is our garbage), while
    /// `unreadable` must be handled non-destructively — the entry may be intact
    /// behind a transient I/O or permission failure.
    enum MetadataAttributeResult {
        case present(CacheMetadata)
        case absent
        case corrupt
        case unreadable
    }

    /// Reads cache metadata from a file's extended attributes, errno-aware.
    ///
    /// A `getxattr` failure is only treated as "no attribute" for `ENOATTR` /
    /// `ENOTSUP` / `ENOENT`; any other errno (EIO, EACCES, …) reports
    /// ``MetadataAttributeResult/unreadable`` so callers don't destroy an intact
    /// entry over a transient failure.
    ///
    /// - Parameter fileURL: The URL of the file to read metadata from.
    /// - Returns: The classified read result.
    static func readMetadataAttribute(at fileURL: URL) -> MetadataAttributeResult {
        fileURL.withUnsafeFileSystemRepresentation { path -> MetadataAttributeResult in
            guard let path else { return .unreadable }

            // Query the size of the attribute without reading its data
            let size = getxattr(path, metadataAttributeName, nil, 0, 0, 0)
            guard size >= 0 else {
                switch errno {
                case ENOATTR, ENOTSUP, ENOENT:
                    return .absent
                default:
                    return .unreadable
                }
            }

            // Allocate buffer and read the attribute data. errno is captured
            // inside the closure, immediately after the call — buffer teardown
            // between the call and a later read could clobber it, and a clobber
            // landing on ENOATTR would misclassify a transient failure as
            // definitively absent (a destructive path).
            var data = Data(count: size)
            let (result, readErrno) = data.withUnsafeMutableBytes { buffer -> (Int, Int32) in
                let bytesRead = getxattr(path, metadataAttributeName, buffer.baseAddress, size, 0, 0)
                return (bytesRead, errno)
            }
            guard result >= 0 else {
                switch readErrno {
                case ENOATTR, ENOTSUP, ENOENT:
                    return .absent
                default:
                    return .unreadable
                }
            }
            // A size change between the two calls means someone is mutating the
            // attribute under us — treat as transient, not as damage to purge.
            guard result == size else { return .unreadable }

            // Decode the JSON-encoded metadata. The attribute name is ours, so a
            // decode failure means our own metadata is garbage — a deliberate
            // destructive branch (callers purge it as legacy).
            guard let metadata = try? JSONDecoder.shared.decode(CacheMetadata.self, from: data) else {
                return .corrupt
            }
            return .present(metadata)
        }
    }

    /// Returns whether the file carries the DiskCache metadata attribute.
    ///
    /// Used by `CacheMigrationManager` to scope version-bump purges to files this
    /// subsystem owns: `present` and `corrupt` both prove ownership (the attribute
    /// name is ours), while `absent` and `unreadable` files are left alone.
    static func hasCacheMetadata(at fileURL: URL) -> Bool {
        switch readMetadataAttribute(at: fileURL) {
        case .present, .corrupt:
            true
        case .absent, .unreadable:
            false
        }
    }

    /// Writes cache metadata to a file's extended attributes.
    ///
    /// Uses the POSIX `setxattr` API to store the JSON-encoded metadata
    /// in the file's extended attributes.
    ///
    /// - Parameters:
    ///   - metadata: The metadata to store.
    ///   - fileURL: The URL of the file to write metadata to.
    /// - Returns: `true` when the attribute was written; `false` on encoding or
    ///   `setxattr` failure, so callers can avoid installing a metadata-less file.
    @discardableResult
    static func writeMetadataAttribute(_ metadata: CacheMetadata, to fileURL: URL) -> Bool {
        // Encode metadata to JSON
        guard let data = try? JSONEncoder().encode(metadata) else { return false }

        // Write the encoded data to the file's extended attributes
        return fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return data.withUnsafeBytes { buffer in
                let result = setxattr(path, metadataAttributeName, buffer.baseAddress, buffer.count, 0, 0)
                if result == -1 {
                    Log(.error, category: .caching, "Failed to write cache metadata xattr for \(fileURL.lastPathComponent): errno \(errno)")
                }
                return result == 0
            }
        }
    }

    /// Constructs the file URL for a cache key.
    ///
    /// - Parameter key: The cache key.
    /// - Returns: The URL where the cached data would be stored, or `nil` if
    ///   the cache directory is unavailable.
    private func fileURL(for key: String) -> URL? {
        cacheDirectory?.appendingPathComponent(key)
    }

    // MARK: - Cache Protocol Implementation

    /// Retrieves metadata for a cached entry.
    ///
    /// Convenience over ``metadataResult(for:)`` for callers that don't need to
    /// distinguish absence from a transient read failure.
    func metadata(for key: String) -> CacheMetadata? {
        guard case .present(let metadata) = metadataResult(for: key) else {
            return nil
        }
        return metadata
    }

    /// Retrieves metadata for a cached entry, distinguishing absence from failure.
    ///
    /// A file definitively missing its metadata attribute (or carrying corrupt
    /// metadata JSON) is a legacy/damaged entry and is purged. A transient read
    /// failure (EIO, EACCES, …) is reported as ``MetadataReadResult/unreadable``
    /// and the file is left untouched — deleting it would destroy an intact entry
    /// over a passing error.
    func metadataResult(for key: String) -> MetadataReadResult {
        guard let fileURL = fileURL(for: key),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return .absent
        }

        switch Self.readMetadataAttribute(at: fileURL) {
        case .present(let metadata):
            return .present(metadata)
        case .absent:
            Log(.info, category: .caching, "No xattr metadata for \(key), purging old-format file")
            try? FileManager.default.removeItem(at: fileURL)
            return .absent
        case .corrupt:
            Log(.warning, category: .caching, "Corrupt xattr metadata for \(key), purging damaged entry")
            try? FileManager.default.removeItem(at: fileURL)
            return .absent
        case .unreadable:
            Log(.warning, category: .caching, "Metadata xattr unreadable for \(key) (errno-classified transient failure); leaving entry intact")
            return .unreadable
        }
    }

    /// Retrieves cached data for a key.
    ///
    /// Delegates legacy purging and failure classification to
    /// ``metadataResult(for:)``; data is only served for entries whose metadata
    /// is definitively present.
    func data(for key: String) -> Data? {
        guard let fileURL = fileURL(for: key) else { return nil }

        guard case .present = metadataResult(for: key) else {
            return nil
        }

        // Read the file contents
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            ErrorReporting.shared.report(error, context: "DiskCache data(for:): failed to read file", category: .caching)
            return nil
        }
    }

    /// Stores data with associated metadata.
    ///
    /// If the cache directory is unavailable, falls back to in-memory
    /// storage using `NSCache` (without metadata support).
    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        guard let fileURL = fileURL(for: key) else {
            // Cache directory unavailable - log error (except on simulator)
            #if !targetEnvironment(simulator)
            let error: DiskCacheError = "Failed to find Cache Directory."
            ErrorReporting.shared.report(error, context: "DiskCache set(_:metadata:for:)", category: .caching)
            #endif

            // Fall back to in-memory cache (no metadata/TTL support)
            if let data = data as? NSData {
                cache.setObject(data, forKey: key as NSString)
            } else {
                cache.removeObject(forKey: key as NSString)
            }
            return
        }

        if let data {
            // Ensure the backing directory exists. External cleanup (or a bug in
            // it) can remove the directory out from under a live DiskCache —
            // CacheMigrationManager deliberately preserves directory nodes on a
            // version bump, but this guard keeps writes safe regardless. Without
            // it, the temp-file write below would fail with ENOENT.
            ensureCacheDirectoryExists()
            writeAtomically(data, metadata: metadata, to: fileURL)
        } else {
            // Nil data means remove the entry
            remove(for: key)
        }
    }

    /// Filename prefix for in-flight temp files used by atomic writes.
    ///
    /// Dot-prefixed so the files are hidden, and distinctive so enumeration can
    /// exclude any orphan left behind by a crash mid-write.
    private static let tempFilePrefix = ".tmp-"

    /// Returns whether a directory entry is an in-flight (or orphaned) temp file.
    ///
    /// Internal so `CacheMigrationManager` can exempt in-flight temps from the
    /// version-bump purge (they carry the ownership xattr before rename; deleting
    /// one makes another process's rename fail and loses its write).
    static func isTempFile(_ fileURL: URL) -> Bool {
        fileURL.lastPathComponent.hasPrefix(tempFilePrefix)
    }

    /// Writes data and its metadata xattr atomically.
    ///
    /// Writing directly to the destination is not atomic: `createFile` replaces the
    /// inode (destroying any existing metadata xattr) before `setxattr` runs, so a
    /// crash — or a concurrent reader — in that window sees an xattr-less file,
    /// which the legacy-purge path then deletes. Instead, the data is written to a
    /// temp file in the same directory, the xattr is attached to the temp, and
    /// `rename(2)` moves it over the destination: rename is atomic on APFS/HFS+ and
    /// carries xattrs with the inode, so readers see either the old complete entry
    /// or the new one, never an intermediate state.
    private func writeAtomically(_ data: Data, metadata: CacheMetadata, to fileURL: URL) {
        let tempURL = fileURL
            .deletingLastPathComponent()
            .appending(path: Self.tempFilePrefix + UUID().uuidString)

        do {
            try data.write(to: tempURL)
        } catch {
            ErrorReporting.shared.report(error, context: "DiskCache atomic write: temp file", category: .caching)
            // A partial temp may have landed before the failure — don't leak it.
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        // If the metadata xattr can't be attached, renaming would install an
        // xattr-less file that the legacy purge deletes on next read — abandon
        // the write instead, preserving the old complete entry. Reported through
        // ErrorReporting: a persistent setxattr outage silently drops every
        // cache write, which must be visible beyond os_log.
        guard Self.writeMetadataAttribute(metadata, to: tempURL) else {
            let error: DiskCacheError = "Abandoned cache write: failed to attach metadata xattr."
            ErrorReporting.shared.report(
                error,
                context: "DiskCache writeAtomically",
                category: .caching,
                additionalData: ["file": fileURL.lastPathComponent]
            )
            try? FileManager.default.removeItem(at: tempURL)
            return
        }

        let renameResult = tempURL.withUnsafeFileSystemRepresentation { source in
            fileURL.withUnsafeFileSystemRepresentation { destination -> Int32 in
                guard let source, let destination else { return -1 }
                return rename(source, destination)
            }
        }

        if renameResult != 0 {
            Log(.error, category: .caching, "Failed to rename temp file into place for \(fileURL.lastPathComponent): errno \(errno)")
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    /// Performs storage maintenance: sweeps orphaned atomic-write temp files.
    ///
    /// Called from `CacheCoordinator`'s async init-purge task rather than from
    /// `DiskCache.init` — the first touch of a static coordinator can happen on
    /// the main actor at launch, and directory enumeration doesn't belong there.
    func performMaintenance() {
        guard let cacheDirectory else { return }
        sweepStaleTempFiles(in: cacheDirectory)
    }

    /// Deletes orphaned atomic-write temp files older than one hour.
    ///
    /// The age threshold is load-bearing: a fresh temp file may be another
    /// process's in-flight write (the shared App Group container is written by
    /// widgets and extensions too), so only temps stale enough to be crash
    /// leftovers are swept. A writer suspended for over an hour losing its temp
    /// is accepted — the cost is one self-healing cache entry.
    ///
    /// At root-scoped directories (shared with other subsystems) a name-only
    /// `.tmp-` match could hit foreign files, so ownership must additionally be
    /// proven by our metadata xattr; subdirectory-scoped caches own their
    /// directory and sweep every stale temp (including xattr-less partial
    /// writes, which at a root are accepted as an unsweepable micro-leak).
    private func sweepStaleTempFiles(in directory: URL) {
        let cutoff = Date.now.addingTimeInterval(-60 * 60)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        for fileURL in contents where Self.isTempFile(fileURL) {
            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            guard let modified, modified < cutoff else { continue }
            guard ownsCacheDirectoryExclusively || Self.hasCacheMetadata(at: fileURL) else { continue }
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Recreates the backing cache directory if it was removed externally.
    ///
    /// Idempotent — `createDirectory(withIntermediateDirectories: true)` is a
    /// no-op when the directory already exists.
    private func ensureCacheDirectoryExists() {
        guard let cacheDirectory else { return }
        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Removes a cached entry from disk.
    ///
    /// A missing file is treated as "already removed" rather than an error —
    /// `MigratingDiskCache` removes from both primary and legacy locations, and
    /// every entry that lives in only one of them would otherwise log an ENOENT.
    func remove(for key: String) {
        guard let fileURL = fileURL(for: key) else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            Log(.error, category: .caching, "Failed to remove \(fileURL) from disk: \(error)")
        }
    }

    /// Returns metadata for all cached entries.
    ///
    /// Iterates through the cache directory and reads metadata from each
    /// file's extended attributes. Files without metadata are skipped
    /// (they will be purged when accessed directly).
    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        guard let cacheDirectory else {
            // Cache directory unavailable - log error (except on simulator)
            #if !targetEnvironment(simulator)
            let error: DiskCacheError = "Failed to find Cache Directory."
            ErrorReporting.shared.report(error, context: "DiskCache allMetadata", category: .caching)
            #endif
            return []
        }

        // List all files in the cache directory
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        } catch {
            ErrorReporting.shared.report(error, context: "DiskCache allMetadata", category: .caching)
            return []
        }

        // Extract metadata from each file, skipping files without the metadata
        // xattr and in-flight/orphaned atomic-write temp files.
        return contents.compactMap { fileURL -> (key: String, metadata: CacheMetadata)? in
            guard !Self.isTempFile(fileURL),
                  case .present(let metadata) = Self.readMetadataAttribute(at: fileURL) else { return nil }
            return (fileURL.lastPathComponent, metadata)
        }
    }

    /// Removes all cache entries from disk.
    ///
    /// Only removes files that have the cache metadata extended attribute,
    /// avoiding deletion of unrelated files that might be in the cache directory.
    func clearAll() {
        guard let cacheDirectory else { return }

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            )
            // Only remove files with our metadata xattr (protects unrelated files)
            for fileURL in contents {
                if Self.hasCacheMetadata(at: fileURL) {
                    try FileManager.default.removeItem(at: fileURL)
                }
            }
            // Also clear the in-memory fallback cache
            cache.removeAllObjects()
            Log(.info, category: .caching, "Cleared all cache entries from \(cacheDirectory.lastPathComponent)")
        } catch {
            Log(.error, category: .caching, "Failed to clear cache: \(error)")
        }
    }

    /// Calculates the total storage size of all cached entries.
    ///
    /// Only counts files that have the cache metadata extended attribute.
    func totalSize() -> Int64 {
        guard let cacheDirectory else { return 0 }

        var totalBytes: Int64 = 0

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            )
            // Sum sizes of files with our metadata xattr (excluding temp files)
            for fileURL in contents {
                guard !Self.isTempFile(fileURL), Self.hasCacheMetadata(at: fileURL) else { continue }
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalBytes += Int64(resourceValues.fileSize ?? 0)
            }
        } catch {
            Log(.error, category: .caching, "Failed to calculate cache size: \(error)")
        }

        return totalBytes
    }
}
