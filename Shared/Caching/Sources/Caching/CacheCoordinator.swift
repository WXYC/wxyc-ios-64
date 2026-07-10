//
//  CacheCoordinator.swift
//  Caching
//
//  Thread-safe actor for caching operations with TTL-based expiration.
//  Provides the primary public API for the caching system.
//
//  Created by Jake Bromberg on 12/17/18.
//  Copyright © 2018 WXYC. All rights reserved.
//

import Core
import Foundation
import Logger

// MARK: - CacheCoordinator

/// Thread-safe coordinator for caching operations with TTL-based expiration.
///
/// `CacheCoordinator` is an actor that provides the primary public API for the caching system.
/// It wraps underlying ``Cache`` implementations and adds:
/// - Automatic expiration checking on reads
/// - JSON encoding/decoding for `Codable` types
/// - Automatic purging of expired entries at initialization
/// - Error logging and analytics capture
///
/// ## Usage
///
/// The module provides five pre-configured cache coordinators for different data
/// types: ``AlbumArt``, ``ArtworkErrors``, ``Playlist``, ``Metadata``, and
/// ``PlaycutHistory``. All but the last hold re-fetchable data under the caches
/// roots; ``PlaycutHistory`` holds irreplaceable, locally-accreted data in a
/// never-purged Application Support store (exempt from version-bump purges and
/// included in backups), so treat its entries with the data-safety rules of a
/// database, not a cache.
///
/// ```swift
/// // Store album artwork (binary data)
/// await CacheCoordinator.AlbumArt.setData(imageData, for: "artwork-123", lifespan: 86400)
///
/// // Retrieve playlist (Codable value)
/// let playlist: Playlist = try await CacheCoordinator.Playlist.value(for: "current")
///
/// // Cache metadata with custom TTL
/// await CacheCoordinator.Metadata.set(value: metadata, for: "track-info", lifespan: 604800)
/// ```
///
/// ## Expiration Behavior
///
/// Entries automatically expire based on their lifespan. Expired entries are:
/// - Purged at coordinator initialization
/// - Removed lazily when accessed after expiration
/// - Entries with infinite lifespan are also purged at initialization (legacy cleanup)
///
/// ## Thread Safety
///
/// As an actor, all operations are automatically thread-safe and can be called
/// from any isolation context.
public final actor CacheCoordinator {
    // MARK: - Shared Instances

    /// Cache coordinator for album artwork images.
    ///
    /// Stores binary image data (JPEG, PNG) for album art fetched from various sources.
    /// Uses ``MigratingDiskCache`` to store artwork in the shared App Group container,
    /// enabling access from widgets and extensions, while transparently migrating
    /// existing artwork from the app's private caches directory.
    public static let AlbumArt = CacheCoordinator(cache: MigratingDiskCache())

    /// Cache coordinator for artwork fetch errors (negative cache).
    ///
    /// Stored separately from artwork images so errors can be cleared independently
    /// when the fetcher chain is upgraded (e.g. Discogs fallback added).
    public static let ArtworkErrors = CacheCoordinator(cache: DiskCache(subdirectory: "artwork-errors"))

    /// Cache coordinator for playlist data.
    ///
    /// Uses ``MigratingDiskCache`` to migrate data from the app's private caches
    /// directory to the shared App Group container, enabling access from widgets
    /// and extensions.
    public static let Playlist = CacheCoordinator(cache: MigratingDiskCache())

    /// Cache coordinator for playcut metadata.
    ///
    /// Stores supplementary track information like artist details, album info,
    /// and streaming service links.
    public static let Metadata = CacheCoordinator(cache: DiskCache())

    /// Cache coordinator for the rolling playcut history.
    ///
    /// Stored in a dedicated subdirectory (like ``ArtworkErrors``) so the
    /// day-bucketed history and rotation set written by `PlaycutHistoryStore`
    /// age out via TTL without interference from other cache traffic. Rooted
    /// in Application Support rather than Caches: the history is accreted
    /// locally over months and cannot be re-fetched, so it must not be exposed
    /// to system cache purges.
    public static let PlaycutHistory = CacheCoordinator(
        cache: DiskCache(location: .applicationSupport(subdirectory: "playcut-history"))
    )

    // MARK: - Error Types

    /// Errors that can occur during cache operations.
    public enum Error: String, LocalizedError, Codable {
        /// No cached entry exists for the requested key, or the entry has expired.
        case noCachedResult

        /// An entry exists for the requested key but its data could not be read.
        ///
        /// Distinct from ``noCachedResult`` so callers doing read-merge-write
        /// (e.g. `PlaycutHistoryStore`) can skip the write instead of truncating
        /// an intact entry after a transient read failure.
        case readFailed
    }

    // MARK: - Initialization

    /// Creates a cache coordinator with the specified cache implementation.
    ///
    /// On initialization, the coordinator spawns a background task to purge expired entries
    /// and entries with infinite lifespan (legacy entries from older cache formats).
    ///
    /// - Parameters:
    ///   - cache: The underlying cache implementation to use for storage.
    ///   - clock: The clock to use for time-based operations. Defaults to ``SystemClock``.
    public init(cache: Cache, clock: Clock = SystemClock()) {
        self.cache = cache
        self.clock = clock

        // Spawn a background task to purge expired entries at initialization.
        // This ensures stale data is cleaned up when the app launches. All write
        // methods await this task, so a write can never be swept by the purge;
        // the re-check below additionally defends against another coordinator
        // (e.g. a widget process) recycling a key mid-purge.
        self.purgeTask = Task { [cache, clock] in
            let currentTime = clock.now
            for (key, metadata) in cache.allMetadata() {
                guard Self.shouldPurge(metadata, at: currentTime) else { continue }
                // Re-check the live metadata immediately before removal, and only
                // remove on a DEFINITIVE read: a fresh write may have recycled the
                // key since the snapshot, and a transiently unreadable entry (e.g.
                // MigratingDiskCache's primary behind an I/O failure, with the
                // snapshot showing an expired lingering legacy copy) must be
                // spared rather than removed from every store.
                guard case .present(let current) = cache.metadataResult(for: key),
                      Self.shouldPurge(current, at: clock.now) else {
                    continue
                }
                cache.remove(for: key)
            }

            // Storage maintenance (e.g. stale temp-file sweeping) runs here, off
            // the caller's actor — DiskCache.init can execute on the main actor.
            cache.performMaintenance()
        }
    }

    /// Whether the init purge should remove an entry: it has expired, or it is a
    /// legacy entry with infinite lifespan (older cache formats used infinity;
    /// current writers always use finite lifespans).
    private static func shouldPurge(_ metadata: CacheMetadata, at time: TimeInterval) -> Bool {
        metadata.isExpired(at: time) || metadata.lifespan == .infinity
    }

    // MARK: - Private Properties

    /// The underlying cache implementation for storage operations.
    private var cache: Cache

    /// Clock used for time-based operations (expiration checks, timestamps).
    private let clock: Clock

    /// Background task that purges expired entries at initialization.
    private let purgeTask: Task<Void, Never>

    /// Shared JSON encoder for serializing Codable values.
    private static let encoder = JSONEncoder()

    /// Shared JSON decoder for deserializing Codable values.
    private static let decoder = JSONDecoder.shared

    // MARK: - Binary Data Operations

    /// Retrieves raw binary data from the cache.
    ///
    /// Use this method for non-Codable data like images. The method checks
    /// expiration before returning data and removes expired entries.
    ///
    /// - Parameter key: The unique identifier for the cached entry.
    /// - Returns: The cached binary data.
    /// - Throws: ``Error/noCachedResult`` if no entry exists or it has expired.
    public func data(for key: String) throws -> Data {
        #if DEBUG
        assert(!key.isEmpty, "Cache key cannot be empty")
        #endif

        // Classify the metadata read and check expiration
        let _ = try validMetadata(for: key)

        // Retrieve the actual data
        guard let data = cache.data(for: key) else {
            throw readError(for: key)
        }

        return data
    }

    /// Reads and classifies an entry's metadata, enforcing expiration.
    ///
    /// - Throws: ``Error/noCachedResult`` for absent or expired entries (expired
    ///   entries are removed), ``Error/readFailed`` when the metadata exists but
    ///   could not be read — the entry is left untouched.
    private func validMetadata(for key: String) throws -> CacheMetadata {
        switch cache.metadataResult(for: key) {
        case .absent:
            throw Error.noCachedResult
        case .unreadable:
            throw Error.readFailed
        case .present(let metadata):
            // Check if the entry has expired
            guard !metadata.isExpired(at: clock.now) else {
                // Clean up expired entry and report as missing
                cache.remove(for: key)
                throw Error.noCachedResult
            }
            return metadata
        }
    }

    /// Classifies a nil data read for a key whose metadata was just seen.
    ///
    /// If metadata is still present (or unreadable) the entry is intact but
    /// unreadable — ``Error/readFailed``. If the metadata has vanished the entry
    /// was removed out from under us (legacy purge, concurrent delete), which
    /// reads as true absence.
    private func readError(for key: String) -> Error {
        if case .absent = cache.metadataResult(for: key) {
            .noCachedResult
        } else {
            .readFailed
        }
    }

    /// Stores raw binary data in the cache with a specified lifespan.
    ///
    /// Use this method for non-Codable data like images. Pass `nil` for `data`
    /// to remove an existing entry.
    ///
    /// - Note: The first write after initialization awaits the one-shot init
    ///   purge (metadata-only, milliseconds) — deliberate, so the purge's stale
    ///   snapshot can never sweep a freshly written key.
    ///
    /// - Parameters:
    ///   - data: The binary data to cache, or `nil` to remove the entry.
    ///   - key: The unique identifier for the cached entry.
    ///   - lifespan: How long the entry should remain valid, in seconds.
    public func setData(_ data: Data?, for key: String, lifespan: TimeInterval) async {
        // Writes strictly follow the init purge so its metadata snapshot can
        // never sweep a key this write just recycled.
        await purgeTask.value

        // Passing nil removes the entry
        guard let data else {
            cache.remove(for: key)
            return
        }

        // Create metadata with current timestamp and store
        let metadata = CacheMetadata(timestamp: clock.now, lifespan: lifespan)
        cache.set(data, metadata: metadata, for: key)
    }

    // MARK: - Codable Value Operations

    /// Retrieves a `Codable` value from the cache.
    ///
    /// The cached data is automatically decoded from JSON. Expired entries
    /// are removed before throwing an error.
    ///
    /// - Parameter key: The unique identifier for the cached entry.
    /// - Returns: The decoded value of type `Value`.
    /// - Throws: ``Error/noCachedResult`` if no entry exists or it has expired,
    ///   or a `DecodingError` if the data cannot be decoded.
    public func value<Value: Codable>(for key: String) async throws -> Value {
        #if DEBUG
        assert(!key.isEmpty, "Cache key cannot be empty")
        #endif

        // Classify the metadata read and check expiration
        let _ = try validMetadata(for: key)

        // Retrieve the raw data
        guard let data = cache.data(for: key) else {
            throw readError(for: key)
        }

        // Decode the JSON data into the requested type.
        // On DecodingError, evict the corrupt entry to prevent repeated failures
        // from the same stale data (e.g., after a schema change adds a required field).
        do {
            return try Self.decoder.decode(Value.self, from: data)
        } catch let error as DecodingError {
            cache.remove(for: key)
            ErrorReporting.shared.report(
                error,
                context: "CacheCoordinator evicted corrupt entry",
                category: .caching,
                additionalData: [
                    "value type": String(describing: Value.self),
                    "key": key
                ]
            )
            throw error
        } catch {
            ErrorReporting.shared.report(
                error,
                context: "CacheCoordinator decode value",
                category: .caching,
                additionalData: [
                    "value type": String(describing: Value.self),
                    "key": key
                ]
            )
            throw error
        }
    }

    /// Stores a `Codable` value in the cache with a specified lifespan.
    ///
    /// The value is automatically encoded to JSON before storage. Pass `nil`
    /// for `value` to remove an existing entry.
    ///
    /// - Note: The first write after initialization awaits the one-shot init
    ///   purge (metadata-only, milliseconds) — deliberate, so the purge's stale
    ///   snapshot can never sweep a freshly written key.
    ///
    /// - Parameters:
    ///   - value: The value to cache, or `nil` to remove the entry.
    ///   - key: The unique identifier for the cached entry.
    ///   - lifespan: How long the entry should remain valid, in seconds.
    public func set<Value: Codable>(value: Value?, for key: String, lifespan: TimeInterval) async {
        // Writes strictly follow the init purge so its metadata snapshot can
        // never sweep a key this write just recycled.
        await purgeTask.value

        // Passing nil removes the entry
        guard let value else {
            cache.remove(for: key)
            return
        }

        // Encode the value to JSON and store with metadata
        do {
            let data = try Self.encoder.encode(value)
            let metadata = CacheMetadata(timestamp: clock.now, lifespan: lifespan)
            cache.set(data, metadata: metadata, for: key)
        } catch {
            ErrorReporting.shared.report(
                error,
                context: "CacheCoordinator encode value",
                category: .caching,
                additionalData: [
                    "value type": String(describing: Value.self),
                    "key": key
                ]
            )
        }
    }

    // MARK: - Testing Support

    /// Waits for the initial purge operation to complete.
    ///
    /// The coordinator automatically purges expired entries at initialization.
    /// This method allows tests to await that operation's completion before
    /// verifying cache state.
    ///
    /// - Note: In production code, you typically don't need to call this method
    ///   as the purge happens asynchronously in the background.
    public func waitForPurge() async {
        await purgeTask.value
    }

    // MARK: - Key Enumeration

    /// Returns all cache entries with their metadata.
    ///
    /// Keys round-trip verbatim: every key returned here can be passed back to
    /// ``value(for:)`` or ``data(for:)``, which makes structured key schemes
    /// enumerable — e.g. `PlaycutHistoryStore` prefixes its day buckets and
    /// filters this list by prefix. Also used by migration operations that need
    /// to iterate over and transform entries.
    ///
    /// Entries are returned regardless of expiration; expired entries are
    /// removed lazily when read through ``value(for:)`` / ``data(for:)``.
    ///
    /// - Returns: An array of tuples containing the key and metadata for each entry.
    public func allEntries() -> [(key: String, metadata: CacheMetadata)] {
        cache.allMetadata()
    }

    // MARK: - Low-Level Access (for Migrations)

    /// Retrieves raw data for a key without checking expiration.
    ///
    /// Unlike ``data(for:)``, this method does not check expiration status,
    /// making it useful for migrations that need to process all entries
    /// including expired ones.
    ///
    /// - Parameter key: The unique identifier for the cached entry.
    /// - Returns: The cached data if found, or `nil` if the entry doesn't exist.
    public func rawData(for key: String) -> Data? {
        cache.data(for: key)
    }

    /// Stores data with explicit metadata, preserving the original timestamp and lifespan.
    ///
    /// Unlike ``setData(_:for:lifespan:)``, this method uses the provided metadata
    /// directly without creating a new timestamp. This is useful for migrations
    /// that transform cache contents without resetting expiration times.
    ///
    /// - Parameters:
    ///   - data: The data to store.
    ///   - metadata: The metadata to associate with the entry.
    ///   - key: The unique identifier for the cached entry.
    public func setDataPreservingMetadata(_ data: Data, metadata: CacheMetadata, for key: String) async {
        // Writes strictly follow the init purge so its metadata snapshot can
        // never sweep a key this write just recycled.
        await purgeTask.value
        cache.set(data, metadata: metadata, for: key)
    }

    // MARK: - Storage Management

    /// Removes all entries from this cache.
    ///
    /// Use this method to clear the entire cache, such as when the user
    /// requests a cache reset from settings.
    public func clearAll() {
        cache.clearAll()
    }

    /// Returns the total storage size of all cached entries in bytes.
    ///
    /// - Returns: The combined size of all cached files.
    public func totalSize() -> Int64 {
        cache.totalSize()
    }
}

#if false
extension FileManager {
    func nukeFileSystem() {
        if let cachesURL = urls(for: .cachesDirectory, in: .userDomainMask).first {
            do {
                let subdirectories = try contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil)

                for subdirectory in subdirectories {
                    var isDirectory: ObjCBool = false
                    if fileExists(atPath: subdirectory.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        try removeItem(at: subdirectory)
                        Log(.info, "Deleted subdirectory: \(subdirectory.lastPathComponent)")
                    }
                }
            } catch {
                Log(.error, "Error clearing subdirectories: \(error)")
            }
        }
    }


    func listFilesRecursively(at url: URL) {
        do {
            let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
            let directoryContents = try contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])

            for item in directoryContents {
                let resourceValues = try item.resourceValues(forKeys: Set(resourceKeys))

                if resourceValues.isDirectory == true {
                    Log(.info, "📂 Directory: \(item.lastPathComponent)")
                    listFilesRecursively(at: item)  // Recursive call for subdirectories
                } else {
                    let fileSize = resourceValues.fileSize ?? 0
                    Log(.info, "📄 File: \(item.lastPathComponent) - \(fileSize) bytes")
                }
            }
        } catch {
            Log(.error, "Error listing directory contents: \(error)")
        }

        let directories: [SearchPathDirectory] = [
            .applicationDirectory,
            .demoApplicationDirectory,
            .developerApplicationDirectory,
            .adminApplicationDirectory,
            .libraryDirectory,
            .developerDirectory,
            .userDirectory,
            .documentationDirectory,
            .documentDirectory,
            .coreServiceDirectory,
            .autosavedInformationDirectory,
            .desktopDirectory,
            .cachesDirectory,
            .applicationSupportDirectory,
            .downloadsDirectory,
            .inputMethodsDirectory,
            .moviesDirectory,
            .musicDirectory,
            .picturesDirectory,
            .printerDescriptionDirectory,
            .sharedPublicDirectory,
            .preferencePanesDirectory,
            .itemReplacementDirectory,
            .allApplicationsDirectory,
            .allLibrariesDirectory,
        ]

        for d in directories {
            if let documentsURL = FileManager.default.urls(for: d, in: .userDomainMask).first {
                Log(.info, "Listing contents of: \(documentsURL.path)")
                listFilesRecursively(at: documentsURL)
            }
        }
    }
}
#endif
