import Foundation

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
protocol Cache: Sendable {
    /// Retrieves metadata for a cached entry without loading the data.
    ///
    /// This method reads only the metadata (timestamp and lifespan) for an entry,
    /// which is useful for checking expiration status without the overhead of
    /// loading the full cached data.
    ///
    /// - Parameter key: The unique identifier for the cached entry.
    /// - Returns: The metadata if the entry exists, or `nil` if not found.
    func metadata(for key: String) -> CacheMetadata?

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
    /// This method is used for cache pruning operations. It reads only metadata,
    /// never file contents, making it efficient for iterating over large caches.
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
}
