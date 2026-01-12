import Foundation

// MARK: - CacheMetadata

/// Metadata associated with a cached entry for TTL-based expiration.
///
/// Each cached entry stores metadata alongside its data to track when the entry
/// was created and how long it should remain valid. This enables automatic
/// expiration of stale data.
///
/// ## Storage
///
/// When using ``DiskCache``, metadata is stored as a file extended attribute
/// (`xattr`) rather than in a separate file. This keeps metadata close to the
/// data while avoiding the overhead of additional file operations.
///
/// ## Expiration
///
/// An entry is considered expired when `currentTime - timestamp > lifespan`.
/// Use ``isExpired(at:)`` with a clock value for testable code, or the
/// convenience ``isExpired`` property for production use.
///
/// ## Example
///
/// ```swift
/// // Create metadata for an entry that expires in 24 hours
/// let metadata = CacheMetadata(lifespan: 86400)
///
/// // Check expiration with a specific time (for testing)
/// let futureTime = metadata.timestamp + 100000
/// metadata.isExpired(at: futureTime) // true
///
/// // Check expiration with current system time
/// metadata.isExpired // false (assuming just created)
/// ```
public struct CacheMetadata: Codable, Sendable {
    /// The time when this cache entry was created.
    ///
    /// Stored as seconds since the reference date (January 1, 2001).
    public let timestamp: TimeInterval

    /// How long this entry should remain valid, in seconds.
    ///
    /// After `lifespan` seconds have elapsed since `timestamp`, the entry
    /// is considered expired and may be removed from the cache.
    public let lifespan: TimeInterval

    /// Creates new cache metadata.
    ///
    /// - Parameters:
    ///   - timestamp: When the entry was created. Defaults to the current time.
    ///   - lifespan: How long the entry should remain valid, in seconds.
    public init(timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate, lifespan: TimeInterval) {
        self.timestamp = timestamp
        self.lifespan = lifespan
    }

    /// Checks if this entry has expired relative to a given time.
    ///
    /// Use this method when you need testable time-based logic by passing
    /// a ``Clock`` value.
    ///
    /// - Parameter currentTime: The time to check against, as seconds since reference date.
    /// - Returns: `true` if the entry has exceeded its lifespan.
    public func isExpired(at currentTime: TimeInterval) -> Bool {
        currentTime - timestamp > lifespan
    }

    /// Checks if this entry has expired using the current system time.
    ///
    /// This is a convenience property for production code. For testable code,
    /// prefer using ``isExpired(at:)`` with an injected clock.
    public var isExpired: Bool {
        isExpired(at: Date.timeIntervalSinceReferenceDate)
    }
}
