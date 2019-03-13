import Foundation

let DefaultLifespan: TimeInterval = 30

private let encoder = JSONEncoder()
private let decoder = JSONDecoder()

public final class CacheCoordinator {
    public static let WXYCPlaylist = CacheCoordinator(cache: UserDefaults.WXYC)
    public static let AlbumArt = CacheCoordinator(cache: ImageCache())
    
    private var cache: Cache
    private let accessQueue = DispatchQueue(label: "org.wxyc.cacheCoordinator.access")
    
    internal init(cache: Cache) {
        self.cache = cache
    }
    
    // MARK: Public getters
    
    public func getValue<Key: Hashable, Value: Codable>(for key: Key) -> Future<Value> {
        return self.getValue(for: String(key.hashValue))
    }
    
    public func set<Key: Hashable, Value: Codable>(value: Value?, for key: Key, lifespan: TimeInterval) {
        self.set(value: value, for: String(key.hashValue), lifespan: lifespan)
    }
    
    // MARK: Private
    
    private func getValue<Value: Codable>(for key: String) -> Future<Value> {
        return self.accessQueue.async {
            guard let encodedCachedRecord = self.cache[key] else {
                throw ServiceErrors.noCachedResult
            }
            
            guard let cachedRecord = try? decoder.decode(CachedRecord<Value>.self, from: encodedCachedRecord) else {
                throw ServiceErrors.noCachedResult
            }
            
            guard !cachedRecord.isExpired else {
                self.set(value: nil as Value?, for: key, lifespan: .distantFuture) // Nil-out expired record
                
                throw ServiceErrors.noCachedResult
            }
            
            return cachedRecord.value
        }
    }
    
    private func set<Value: Codable>(value: Value?, for key: String, lifespan: TimeInterval) {
        self.accessQueue.async {
            if let value = value {
                let cachedRecord = CachedRecord(value: value, lifespan: lifespan)
                
                let encodedCachedRecord = try? encoder.encode(cachedRecord)
                
                self.cache[key] = encodedCachedRecord
            } else {
                self.cache[key] = nil as Data?
            }
        }
    }
}

public extension DispatchQueue {
    func async<T>(_ work: @escaping () throws -> T) -> Future<T> {
        let promise = Promise<T>()
        
        self.async {
            do {
                let value = try work()
                promise.resolve(with: value)
            } catch {
                promise.reject(with: error)
            }
        }
        
        return promise
    }
}
