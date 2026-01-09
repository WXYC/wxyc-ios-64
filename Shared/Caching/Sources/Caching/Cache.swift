import Foundation

/// Protocol defining the interface for cache implementations.
///
/// Conforming types provide key-value storage with metadata support for TTL-based expiration.
protocol Cache: Sendable {
    /// Read metadata only (from xattr, not file contents)
    func metadata(for key: String) -> CacheMetadata?

    /// Read data (file contents)
    func data(for key: String) -> Data?

    /// Write both data and metadata
    func set(_ data: Data?, metadata: CacheMetadata, for key: String)

    /// Delete entry
    func remove(for key: String)

    /// For pruning - only reads metadata, never file contents
    func allMetadata() -> [(key: String, metadata: CacheMetadata)]
}
