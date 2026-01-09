import Foundation
import Logger
import PostHog
import Analytics

struct DiskCache: Cache, @unchecked Sendable {
    struct DiskCacheError: LocalizedError, ExpressibleByStringLiteral, CustomStringConvertible {
        let message: String

        var description: String { message }
        var errorDescription: String? { message }

        init(stringLiteral value: String) {
            self.message = value
        }
    }

    private static let metadataAttributeName = "com.wxyc.cache.metadata"
    private static let appGroupID = "group.wxyc.iphone"
    private let cache = NSCache<NSString, NSData>()
    private let cacheDirectory: URL?

    /// Creates a DiskCache.
    /// - Parameter useSharedContainer: If true, uses the App Group shared container (for sharing between app and widget).
    ///                                 If false, uses the app's private caches directory.
    init(useSharedContainer: Bool = false) {
        guard useSharedContainer else {
            self.cacheDirectory = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first

            return
        }

        if let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)
        {
            let cacheDir = container
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)

            try? FileManager.default.createDirectory(
                at: cacheDir,
                withIntermediateDirectories: true
            )

            self.cacheDirectory = cacheDir
        } else {
            #if !targetEnvironment(simulator)
            Log(.error, "App group container not available for '\(Self.appGroupID)'. Check entitlements and provisioning profile.")
            #endif
            self.cacheDirectory = nil
        }
    }

    // MARK: - xattr helpers

    private func getMetadata(for fileURL: URL) -> CacheMetadata? {
        fileURL.withUnsafeFileSystemRepresentation { path -> CacheMetadata? in
            guard let path else { return nil }

            // First, get the size of the attribute
            let size = getxattr(path, Self.metadataAttributeName, nil, 0, 0, 0)
            guard size > 0 else { return nil }

            // Then read the attribute data
            var data = Data(count: size)
            let result = data.withUnsafeMutableBytes { buffer in
                getxattr(path, Self.metadataAttributeName, buffer.baseAddress, size, 0, 0)
            }
            guard result == size else { return nil }

            return try? JSONDecoder().decode(CacheMetadata.self, from: data)
        }
    }

    private func setMetadata(_ metadata: CacheMetadata, for fileURL: URL) {
        guard let data = try? JSONEncoder().encode(metadata) else { return }

        fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            data.withUnsafeBytes { buffer in
                _ = setxattr(path, Self.metadataAttributeName, buffer.baseAddress, buffer.count, 0, 0)
            }
        }
    }

    private func fileURL(for key: String) -> URL? {
        cacheDirectory?.appendingPathComponent(key)
    }

    // MARK: - Cache protocol

    func metadata(for key: String) -> CacheMetadata? {
        guard let fileURL = fileURL(for: key),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // If no xattr exists, this is an old-format file - purge it
        guard let metadata = getMetadata(for: fileURL) else {
            Log(.info, "No xattr metadata for \(key), purging old-format file")
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        return metadata
    }

    func data(for key: String) -> Data? {
        guard let fileURL = fileURL(for: key),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Check for xattr - if missing, purge old-format file
        guard getMetadata(for: fileURL) != nil else {
            Log(.info, "No xattr metadata for \(key), purging old-format file")
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }

        do {
            return try Data(contentsOf: fileURL)
        } catch let error as NSError {
            Log(.error, "Failed to read file \(fileURL): \(error)")
            let postHogError = DiskCacheError(stringLiteral: "Failed to read file \(fileURL): Error Domain=\(error.domain) Code=\(error.code) \(error.localizedDescription)")
            PostHogSDK.shared.capture(error: postHogError, context: "DiskCache data(for:): failed to read file")
            return nil
        }
    }

    func set(_ data: Data?, metadata: CacheMetadata, for key: String) {
        guard let fileURL = fileURL(for: key) else {
            #if !targetEnvironment(simulator)
            let error: DiskCacheError = "Failed to find Cache Directory."
            Log(.error, error.localizedDescription)
            PostHogSDK.shared.capture(error: error, context: "DiskCache set(_:metadata:for:)")
            #endif

            // Fall back to NSCache for data only (no metadata support)
            if let data = data as? NSData {
                cache.setObject(data, forKey: key as NSString)
            } else {
                cache.removeObject(forKey: key as NSString)
            }
            return
        }

        if let data {
            FileManager.default.createFile(atPath: fileURL.path, contents: data)
            setMetadata(metadata, for: fileURL)
        } else {
            remove(for: key)
        }
    }

    func remove(for key: String) {
        guard let fileURL = fileURL(for: key) else { return }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            Log(.error, "Failed to remove \(fileURL) from disk: \(error)")
        }
    }

    func allMetadata() -> [(key: String, metadata: CacheMetadata)] {
        guard let cacheDirectory else {
            #if !targetEnvironment(simulator)
            let error: DiskCacheError = "Failed to find Cache Directory."
            Log(.error, error.localizedDescription)
            PostHogSDK.shared.capture(error: error, context: "DiskCache allMetadata")
            #endif
            return []
        }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil)
        } catch {
            Log(.error, "Failed to read Cache Directory: \(error.localizedDescription)")
            PostHogSDK.shared.capture(error: error, context: "DiskCache allMetadata")
            return []
        }

        return contents.compactMap { fileURL -> (key: String, metadata: CacheMetadata)? in
            guard let metadata = getMetadata(for: fileURL) else { return nil }
            return (fileURL.lastPathComponent, metadata)
        }
    }
}
