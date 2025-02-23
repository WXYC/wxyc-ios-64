import Foundation
import UIKit

let DefaultLifespan: TimeInterval = 30

public final actor CacheCoordinator {
    public static let WXYCPlaylist = CacheCoordinator(cache: UserDefaultsCache())
    public static let AlbumArt = CacheCoordinator(cache: StandardCache())
    
    public static let PurgeRecords: Notification.Name = .init("org.wxyc.iphone.CacheCoordinator.PurgeRecords")
    
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
    where Value: Codable, Key: RawRepresentable, Key.RawValue == String {
        try await self.value(for: key.rawValue)
    }
    
    public func value<Value, Key>(for key: Key) async throws -> Value
        where Value: Codable, Key: Identifiable, Key.ID == Int
    {
        try await self.value(for: String(key.id))
    }
    
    public func value<Value: Codable>(for key: String) async throws -> Value {
        do {
            guard let encodedCachedRecord = self.cache.object(for: key) else {
                throw ServiceErrors.noCachedResult
            }
            
            let cachedRecord = try Self.decoder.decode(CachedRecord<Value>.self, from: encodedCachedRecord)
            
            
            // nil out record, if expired
            guard !cachedRecord.isExpired else {
                self.cache.set(object: nil, for: key) // Nil-out expired record
                
                throw ServiceErrors.noCachedResult
            }
            
            Log(.info, ">>> cache hit!", key, cachedRecord.value)
            
            return cachedRecord.value
        } catch {
            Log(.error, ">>> No value for '\(key)': ", error)
            throw error
        }
    }
    
    public func set<Value, Key>(value: Value?, for key: Key, lifespan: TimeInterval)
        where Value: Codable, Key: RawRepresentable, Key.RawValue == String
    {
        self.set(value: value, for: key.rawValue, lifespan: lifespan)
    }
    
    public func set<Value, Key>(value: Value?, for key: Key, lifespan: TimeInterval)
        where Value: Codable, Key: Identifiable, Key.ID == Int
    {
        self.set(value: value, for: String(key.id), lifespan: lifespan)
    }
    
    public func set<Value: Codable>(value: Value?, for key: String, lifespan: TimeInterval) {
        Log(.info, ">>> Setting value for key '\(key)'")
        Log(.info, "Value is nil: \(value == nil)")
        Log(.info, "Lifespan: \(lifespan)")
        
        if let value = value {
            let cachedRecord = CachedRecord(value: value, lifespan: lifespan)
            let encodedCachedRecord = try? Self.encoder.encode(cachedRecord)
            
            self.cache.set(object: encodedCachedRecord, for: key)
        } else {
            self.cache.set(object: nil, for: key)
        }
    }
    
    // MARK: Private methods
    
    private nonisolated func purgeRecords() {
        Task {
            await self.purgeExpiredRecords()
            await self.purgeDistantFutureRecords()
        }
    }
    
    private func purgeExpiredRecords() {
        for (key, value) in self.cache.allRecords() {
            if let record = try? Self.decoder.decode(CachedRecord<Data>.self, from: value),
               record.isExpired {
                self.cache.set(object: nil, for: key)
            }
        }
    }
    
    private func purgeDistantFutureRecords() {
        for (key, value) in self.cache.allRecords() {
            if let record = try? Self.decoder.decode(CachedRecord<Data>.self, from: value),
               record.lifespan == .distantFuture {
                Log(.info, "Purging distant future record for key '\(key)'")
                self.cache.set(object: nil, for: key)
            }
        }
    }
}
