import Foundation
import UIKit
import Logger
import PostHog
import Analytics

let DefaultLifespan: TimeInterval = 30

public final actor CacheCoordinator {
    public static let Widgets = CacheCoordinator(cache: UserDefaultsCache())
    public static let WXYCPlaylist = CacheCoordinator(cache: UserDefaultsCache())
    public static let AlbumArt = CacheCoordinator(cache: DiskCache())
    
    enum Error: String, LocalizedError, Codable {
        case noCachedResult
    }
    
    internal init(cache: Cache) {
        self.cache = cache
        self.purgeRecords()
    }
    
    // MARK: Private vars
    
    private var cache: Cache
    
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    
    // MARK: Public methods
    
    public func value<Value, Key>(for key: Key) async throws -> Value
        where Value: Codable, Key: RawRepresentable, Key.RawValue == String
    {
        try await self.value(for: key.rawValue)
    }
    
    public func value<Value, Key>(for key: Key) async throws -> Value
        where Value: Codable, Key: Identifiable, Key.ID: LosslessStringConvertible
    {
        try await self.value(for: String(key.id))
    }
    
    public func value<Value: Codable>(for key: String) async throws -> Value {
        do {
            guard let encodedCachedRecord = self.cache.object(for: key) else {
                throw Error.noCachedResult
            }
            
            let cachedRecord: CachedRecord<Value> = try self.decode(value: encodedCachedRecord, forKey: key)
            
            // nil out record, if expired
            guard !cachedRecord.isExpired else {
                self.cache.set(object: nil, for: key) // Nil-out expired record
                
                throw Error.noCachedResult
            }
            
            Log(.info, "cache hit!", key, cachedRecord.value)
            
            return cachedRecord.value
        } catch {
            Log(.error, "No value for '\(key)': ", error)
            throw error
        }
    }
    
    public func set<Value: Codable>(value: Value?, for key: String, lifespan: TimeInterval) {
        Log(.info, "Setting value for key \(key). Value is \(value == nil ? "nil" : "not nil"). Lifespan: \(lifespan). Value type is \(String(describing: Value.self))")
        
        guard let value else {
            self.cache.set(object: nil, for: key)
            return
        }
        
        do {
            let record = CachedRecord(value: value, lifespan: lifespan)
            let encodedRecord = try Self.encoder.encode(record)
            self.cache.set(object: encodedRecord, for: key)
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
    
    // MARK: Private methods
    
    private nonisolated func decode<Value: Decodable>(value: Data, forKey key: String) throws -> CachedRecord<Value> {
        do {
            return try Self.decoder.decode(CachedRecord<Value>.self, from: value)
        } catch {
            Log(.error, "CacheCoordinator failed to decode value for key \"\(key)\": \(error)")
            Log(.error, "\(try Self.decoder.decode(CachedRecord<String>.self, from: value))")
            if Value.self != CachedRecord<ArtworkService.Error>.self {
                PostHogSDK.shared.capture(
                    error: error,
                    context: "CacheCoordinator decode value",
                    additionalData: [
                        "value type": String(describing: Value.self),
                        "key": key
                    ]
                )
            }
            
            throw error
        }
    }
    
    private nonisolated func purgeRecords() {
        Task {
            Log(.info, "Purging records")
            let cache = await self.cache
            for (key, value) in cache.allRecords() {
                do {
                    let record: CachedRecord<String> = try self.decode(value: value, forKey: key)
                    if record.isExpired || record.lifespan == .distantFuture {
                        cache.set(object: nil, for: key)
                    }
                } catch {
                    PostHogSDK.shared.capture(
                        error: error,
                        context: "CacheCoordinator purgeRecords",
                        additionalData: ["key" : key]
                    )
                    Log(.error, "Failed to decode value for \(key): \(error)\nDeleting it anyway.")
                    cache.set(object: nil, for: key)
                }
            }
        }
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
