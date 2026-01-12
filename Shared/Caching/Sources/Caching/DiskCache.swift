import Foundation
import Logger
import PostHog
import Analytics

// MARK: - DiskCache

/// File-based cache implementation using extended attributes for metadata.
///
/// `DiskCache` stores cached data as files on disk, with ``CacheMetadata`` stored
/// as a file extended attribute (`xattr`). This approach keeps metadata close to
/// the data without requiring separate metadata files.
///
/// ## Storage Locations
///
/// `DiskCache` supports two storage locations:
/// - **Private**: The app's caches directory (`~/Library/Caches`)
/// - **Shared**: The App Group container (`group.wxyc.iphone/Library/Caches`)
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
    private let cache = NSCache<NSString, NSData>()

    /// The directory where cache files are stored, or `nil` if unavailable.
    private let cacheDirectory: URL?

    // MARK: - Initialization

    /// Creates a disk cache with the specified storage location.
    ///
    /// - Parameter useSharedContainer: If `true`, uses the App Group shared container
    ///   for storage, enabling access from widgets and extensions. If `false`, uses
    ///   the app's private caches directory.
    ///
    /// - Note: On the simulator, the shared container may not be available. In this
    ///   case, the cache falls back to in-memory storage without logging an error.
    init(useSharedContainer: Bool = false) {
        // Use the private caches directory if shared container not requested
        guard useSharedContainer else {
            self.cacheDirectory = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first

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
        } else {
            // Shared container unavailable - log error (except on simulator)
            #if !targetEnvironment(simulator)
            Log(.error, "App group container not available for '\(Self.appGroupID)'. Check entitlements and provisioning profile.")
            #endif
            self.cacheDirectory = nil
        }
    }

    // MARK: - Extended Attribute Helpers

    /// Reads cache metadata from a file's extended attributes.
    ///
    /// Uses the POSIX `getxattr` API to read the JSON-encoded metadata
    /// stored in the file's extended attributes.
    ///
    /// - Parameter fileURL: The URL of the file to read metadata from.
    /// - Returns: The decoded metadata, or `nil` if the attribute doesn't exist
    ///   or cannot be decoded.
    private func getMetadata(for fileURL: URL) -> CacheMetadata? {
        fileURL.withUnsafeFileSystemRepresentation { path -> CacheMetadata? in
            guard let path else { return nil }

            // Query the size of the attribute without reading its data
            let size = getxattr(path, Self.metadataAttributeName, nil, 0, 0, 0)
            guard size > 0 else { return nil }

            // Allocate buffer and read the attribute data
            var data = Data(count: size)
            let result = data.withUnsafeMutableBytes { buffer in
                getxattr(path, Self.metadataAttributeName, buffer.baseAddress, size, 0, 0)
            }
            guard result == size else { return nil }

            // Decode the JSON-encoded metadata
            return try? JSONDecoder().decode(CacheMetadata.self, from: data)
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
    private func setMetadata(_ metadata: CacheMetadata, for fileURL: URL) {
        // Encode metadata to JSON
        guard let data = try? JSONEncoder().encode(metadata) else { return }

        // Write the encoded data to the file's extended attributes
        fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            data.withUnsafeBytes { buffer in
                _ = setxattr(path, Self.metadataAttributeName, buffer.baseAddress, buffer.count, 0, 0)
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
    /// If the file exists but has no metadata extended attribute, it's
    /// considered a legacy entry and is automatically purged.
    func metadata(for key: String) -> CacheMetadata? {
        guard let fileURL = fileURL(for: key),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Check for metadata xattr - purge legacy files without it
        guard let metadata = getMetadata(for: fileURL) else {
            Log(.info, "No xattr metadata for \(key), purging old-format file")
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        return metadata
    }

    /// Retrieves cached data for a key.
    ///
    /// If the file exists but has no metadata extended attribute, it's
    /// considered a legacy entry and is automatically purged.
    func data(for key: String) -> Data? {
        guard let fileURL = fileURL(for: key),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Check for metadata xattr - purge legacy files without it
        guard getMetadata(for: fileURL) != nil else {
            Log(.info, "No xattr metadata for \(key), purging old-format file")
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        // Read the file contents
        do {
            return try Data(contentsOf: fileURL)
        } catch let error as NSError {
            // Log read failures for debugging and analytics
            Log(.error, "Failed to read file \(fileURL): \(error)")
            let postHogError = DiskCacheError(stringLiteral: "Failed to read file \(fileURL): Error Domain=\(error.domain) Code=\(error.code) \(error.localizedDescription)")
            PostHogSDK.shared.capture(error: postHogError, context: "DiskCache data(for:): failed to read file")
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
            Log(.error, error.localizedDescription)
            PostHogSDK.shared.capture(error: error, context: "DiskCache set(_:metadata:for:)")
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
            // Write data to file and attach metadata as xattr
            FileManager.default.createFile(atPath: fileURL.path, contents: data)
            setMetadata(metadata, for: fileURL)
        } else {
            // Nil data means remove the entry
            remove(for: key)
        }
    }

    /// Removes a cached entry from disk.
    func remove(for key: String) {
        guard let fileURL = fileURL(for: key) else { return }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            Log(.error, "Failed to remove \(fileURL) from disk: \(error)")
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
            Log(.error, error.localizedDescription)
            PostHogSDK.shared.capture(error: error, context: "DiskCache allMetadata")
            #endif
            return []
        }

        // List all files in the cache directory
        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        } catch {
            Log(.error, "Failed to read Cache Directory: \(error.localizedDescription)")
            PostHogSDK.shared.capture(error: error, context: "DiskCache allMetadata")
            return []
        }

        // Extract metadata from each file (skip files without metadata xattr)
        return contents.compactMap { fileURL -> (key: String, metadata: CacheMetadata)? in
            guard let metadata = getMetadata(for: fileURL) else { return nil }
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
                if getMetadata(for: fileURL) != nil {
                    try FileManager.default.removeItem(at: fileURL)
                }
            }
            // Also clear the in-memory fallback cache
            cache.removeAllObjects()
            Log(.info, "Cleared all cache entries from \(cacheDirectory.lastPathComponent)")
        } catch {
            Log(.error, "Failed to clear cache: \(error)")
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
            // Sum sizes of files with our metadata xattr
            for fileURL in contents {
                guard getMetadata(for: fileURL) != nil else { continue }
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                totalBytes += Int64(resourceValues.fileSize ?? 0)
            }
        } catch {
            Log(.error, "Failed to calculate cache size: \(error)")
        }

        return totalBytes
    }
}
