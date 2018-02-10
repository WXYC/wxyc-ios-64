import Foundation

struct CachedRecord<Value: Codable>: Codable {
    let value: Value
    let timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate
    let lifespan: TimeInterval = 30
    
    var isExpired: Bool {
        return Date.timeIntervalSinceReferenceDate - self.timestamp > self.lifespan
    }
}

public final class Cache {
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults) {
        self.defaults = defaults
    }
    
    subscript<Key: RawRepresentable, Value: Codable>(_ key: Key) -> Value? where Key.RawValue == String {
        get {
            guard let encodedCachedRecord = self.defaults.object(forKey: key.rawValue) as? Data else {
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
            if let newValue = newValue {
                let cachedRecord = CachedRecord(value: newValue)
                
                let encoder = JSONEncoder()
                let encodedCachedRecord = try? encoder.encode(cachedRecord)
                
                self.defaults.set(encodedCachedRecord, forKey: key.rawValue)
            } else {
                self.defaults.set(nil, forKey: key.rawValue)
            }
        }
    }
}
