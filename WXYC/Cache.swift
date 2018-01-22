import Foundation

struct CachedRecord<Value: Codable>: Codable {
    let value: Value
    let timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate
    var lifespan: TimeInterval = 30
    
    init(value: Value) {
        self.value = value
    }
    
    var isExpired: Bool {
        return Date.timeIntervalSinceReferenceDate - self.timestamp > self.lifespan
    }
}

final class Cache {
    let defaults: UserDefaults
    
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }
    
    subscript<Value: Codable>(key: String) -> Value? {
        get {
            guard let encodedCachedRecord = self.defaults.object(forKey: key) as? Data else {
                return nil
            }
            
            let decoder = JSONDecoder()
            
            guard let cachedRecord = try? decoder.decode(CachedRecord<Value>.self, from: encodedCachedRecord) else {
                return nil
            }
            
            guard !cachedRecord.isExpired else {
                return nil
            }
            
            return cachedRecord.value
        }
        set {
            guard let newValue = newValue else {
                return
            }
            
            let cachedRecord = CachedRecord(value: newValue)
            
            let encoder = JSONEncoder()
            let encodedCachedRecord = try? encoder.encode(cachedRecord)
            
            self.defaults.set(encodedCachedRecord, forKey: key)
        }
    }
}

extension Cache {
    static var WXYC: Cache {
        return Cache(defaults: UserDefaults(suiteName: "org.wxyc.apps")!)
    }
}
