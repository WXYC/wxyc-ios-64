import Foundation
import Combine

let DefaultLifespan: TimeInterval = 30

public final actor CacheCoordinator {
    public static let WXYCPlaylist = CacheCoordinator(cache: UserDefaults.WXYC)
    public static let AlbumArt = CacheCoordinator(cache: ImageCache())
    
    // MARK: Private vars
    
    private var cache: Cache
    
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()
    
    internal init(cache: Cache) {
        self.cache = cache
    }
    
    // MARK: Public methods
    
    public func value<Value, Key>(for key: Key) async throws -> Value
        where Value: Codable, Key: RawRepresentable, Key.RawValue == String {
            try await self.value(for: key.rawValue)
    }
    
    public func value<Value, Key>(for key: Key) async throws -> Value
        where Value: Codable, Key: Identifiable, Key.ID == Int {
            try await self.value(for: String(key.id))
    }
    
    public func value<Value: Codable>(for key: String) async throws -> Value {
        do {
            guard let encodedCachedRecord = self.cache[key] else {
                throw ServiceErrors.noCachedResult
            }
            
            let cachedRecord = try Self.decoder.decode(CachedRecord<Value>.self, from: encodedCachedRecord)
            
            
            // nil out record, if expired
            guard !cachedRecord.isExpired else {
                self.set(value: nil as Value?, for: key, lifespan: .distantFuture) // Nil-out expired record
                
                throw ServiceErrors.noCachedResult
            }
            
            print(">>> cache hit!", key, cachedRecord.value)
            
            return cachedRecord.value
        } catch {
            print(error)
            throw error
        }
    }
    
    public func set<Value, Key>(value: Value?, for key: Key, lifespan: TimeInterval)
        where Value: Codable, Key: RawRepresentable, Key.RawValue == String {
            return self.set(value: value, for: key.rawValue, lifespan: lifespan)
    }
    
    public func set<Value, Key>(value: Value?, for key: Key, lifespan: TimeInterval)
        where Value: Codable, Key: Identifiable, Key.ID == Int {
            return self.set(value: value, for: String(key.id), lifespan: lifespan)
    }
    
    public func set<Value: Codable>(value: Value?, for key: String, lifespan: TimeInterval) {
        if let value = value {
            let cachedRecord = CachedRecord(value: value, lifespan: lifespan)
            let encodedCachedRecord = try? Self.encoder.encode(cachedRecord)
            
            self.cache[key] = encodedCachedRecord
        } else {
            self.cache[key] = nil as Data?
        }
    }
}
