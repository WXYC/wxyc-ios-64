import Foundation
import Logger
import PostHog
import Analytics

public final actor CacheCoordinator {
    public static let AlbumArt = CacheCoordinator(cache: DiskCache())
    /// Playlist cache uses MigratingDiskCache to migrate from private to shared App Group container
    public static let Playlist = CacheCoordinator(cache: MigratingDiskCache())
    
    public enum Error: String, LocalizedError, Codable {
        case noCachedResult
    }
    
    internal init(cache: Cache, clock: Clock = SystemClock()) {
        self.cache = cache
        self.clock = clock
        self.purgeTask = Task { [cache, clock] in
            let currentTime = clock.now
            for (key, metadata) in cache.allMetadata() {
                if metadata.isExpired(at: currentTime) || metadata.lifespan == .infinity {
                    cache.remove(for: key)
                }
            }
        }
    }

    // MARK: Private vars

    private var cache: Cache
    private let clock: Clock
    private let purgeTask: Task<Void, Never>
    
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: Public methods - Binary data (images, etc.)
    
    /// Retrieve raw binary data from cache
    public func data(for key: String) throws -> Data {
        #if DEBUG
        assert(!key.isEmpty, "Cache key cannot be empty")
        #endif

        guard let metadata = cache.metadata(for: key) else {
            throw Error.noCachedResult
        }

        guard !metadata.isExpired(at: clock.now) else {
            cache.remove(for: key)
            throw Error.noCachedResult
        }

        guard let data = cache.data(for: key) else {
            throw Error.noCachedResult
        }

        return data
    }
        
    /// Store raw binary data in cache
    public func setData(_ data: Data?, for key: String, lifespan: TimeInterval) {
        guard let data else {
            cache.remove(for: key)
            return
        }

        let metadata = CacheMetadata(timestamp: clock.now, lifespan: lifespan)
        cache.set(data, metadata: metadata, for: key)
    }

    // MARK: Public methods - Codable values (playlists, etc.)
    
    /// Retrieve a Codable value from cache
    public func value<Value: Codable>(for key: String) async throws -> Value {
        #if DEBUG
        assert(!key.isEmpty, "Cache key cannot be empty")
        #endif

        guard let metadata = cache.metadata(for: key) else {
            throw Error.noCachedResult
        }

        guard !metadata.isExpired(at: clock.now) else {
            cache.remove(for: key)
            throw Error.noCachedResult
        }

        guard let data = cache.data(for: key) else {
            throw Error.noCachedResult
        }
        
        do {
            return try Self.decoder.decode(Value.self, from: data)
        } catch {
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
    
    /// Store a Codable value in cache
    public func set<Value: Codable>(value: Value?, for key: String, lifespan: TimeInterval) {
        guard let value else {
            cache.remove(for: key)
            return
        }

        do {
            let data = try Self.encoder.encode(value)
            let metadata = CacheMetadata(timestamp: clock.now, lifespan: lifespan)
            cache.set(data, metadata: metadata, for: key)
        } catch {
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
    
    // MARK: - Public Methods (Testing Support)

    /// Waits for the initial purge operation to complete.
    ///
    /// The coordinator automatically purges expired entries at initialization.
    /// This method allows callers to await that operation's completion.
    public func waitForPurge() async {
        await purgeTask.value
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
