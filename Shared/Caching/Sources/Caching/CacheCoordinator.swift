import Foundation
import Logger
import PostHog
import Analytics

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
/// The module provides three pre-configured cache coordinators for different data types:
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
    /// Uses the app's private caches directory.
    public static let AlbumArt = CacheCoordinator(cache: DiskCache())

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

    // MARK: - Error Types

    /// Errors that can occur during cache operations.
    public enum Error: String, LocalizedError, Codable {
        /// No cached entry exists for the requested key, or the entry has expired.
        case noCachedResult
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
    internal init(cache: Cache, clock: Clock = SystemClock()) {
        self.cache = cache
        self.clock = clock

        // Spawn a background task to purge expired entries at initialization.
        // This ensures stale data is cleaned up when the app launches.
        self.purgeTask = Task { [cache, clock] in
            let currentTime = clock.now
            for (key, metadata) in cache.allMetadata() {
                // Remove expired entries and legacy entries with infinite lifespan
                if metadata.isExpired(at: currentTime) || metadata.lifespan == .infinity {
                    cache.remove(for: key)
                }
            }
        }
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
    private static let decoder = JSONDecoder()

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

        // Check if metadata exists for this key
        guard let metadata = cache.metadata(for: key) else {
            throw Error.noCachedResult
        }

        // Check if the entry has expired
        guard !metadata.isExpired(at: clock.now) else {
            // Clean up expired entry and report as missing
            cache.remove(for: key)
            throw Error.noCachedResult
        }

        // Retrieve the actual data
        guard let data = cache.data(for: key) else {
            throw Error.noCachedResult
        }

        return data
    }

    /// Stores raw binary data in the cache with a specified lifespan.
    ///
    /// Use this method for non-Codable data like images. Pass `nil` for `data`
    /// to remove an existing entry.
    ///
    /// - Parameters:
    ///   - data: The binary data to cache, or `nil` to remove the entry.
    ///   - key: The unique identifier for the cached entry.
    ///   - lifespan: How long the entry should remain valid, in seconds.
    public func setData(_ data: Data?, for key: String, lifespan: TimeInterval) {
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

        // Check if metadata exists for this key
        guard let metadata = cache.metadata(for: key) else {
            throw Error.noCachedResult
        }

        // Check if the entry has expired
        guard !metadata.isExpired(at: clock.now) else {
            // Clean up expired entry and report as missing
            cache.remove(for: key)
            throw Error.noCachedResult
        }

        // Retrieve the raw data
        guard let data = cache.data(for: key) else {
            throw Error.noCachedResult
        }
    
        // Decode the JSON data into the requested type
        do {
            return try Self.decoder.decode(Value.self, from: data)
        } catch {
            // Log decode failures for debugging and analytics
            Log(.error, "CacheCoordinator failed to decode value for key \"\(key)\": \(error)")
            PostHogSDK.shared.capture(
                error: error,
                context: "CacheCoordinator decode value",
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
    /// - Parameters:
    ///   - value: The value to cache, or `nil` to remove the entry.
    ///   - key: The unique identifier for the cached entry.
    ///   - lifespan: How long the entry should remain valid, in seconds.
    public func set<Value: Codable>(value: Value?, for key: String, lifespan: TimeInterval) {
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
            // Log encode failures for debugging and analytics
            Log(.error, "Failed to encode value for \(key): \(error)")
            PostHogSDK.shared.capture(
                error: error,
                context: "CacheCoordinator encode value",
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

    // MARK: - Migration Support

    /// Removes all entries with keys matching a specified prefix.
    ///
    /// This method is useful for cleaning up legacy cache entries when
    /// migrating to a new key naming scheme.
    ///
    /// - Parameter prefix: The key prefix to match for removal.
    public func removeEntries(withPrefix prefix: String) async {
        // Wait for initial purge to complete first
        await waitForPurge()

        // Iterate through all entries and remove matching ones
        for (key, _) in cache.allMetadata() {
            if key.hasPrefix(prefix) {
                cache.remove(for: key)
                Log(.info, "Removed cache entry with prefix '\(prefix)': \(key)")
            }
        }
    }

    /// Migrates legacy playcut metadata from the AlbumArt cache.
    ///
    /// In older versions, playcut metadata was stored in `CacheCoordinator.AlbumArt`
    /// with keys prefixed by `playcut-metadata-`. This method removes those entries
    /// since metadata is now stored in `CacheCoordinator.Metadata` with more
    /// granular keys (artist, album, streaming links).
    ///
    /// - Note: Legacy entries have a 7-day TTL, so they will eventually expire
    ///   naturally even if this migration is not run.
    public static func migrateLegacyMetadataCache() async {
        await CacheCoordinator.AlbumArt.removeEntries(withPrefix: "playcut-metadata-")
    }

    // MARK: - Low-Level Access (for Migrations)

    /// Returns all cache entries with their metadata.
    ///
    /// This method provides direct access to cache contents for migration
    /// operations that need to iterate over and transform entries.
    ///
    /// - Returns: An array of tuples containing the key and metadata for each entry.
    public func allEntries() -> [(key: String, metadata: CacheMetadata)] {
        cache.allMetadata()
    }

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
    public func setDataPreservingMetadata(_ data: Data, metadata: CacheMetadata, for key: String) {
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
