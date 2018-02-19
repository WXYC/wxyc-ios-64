import Foundation

let defaultLifespan: TimeInterval = 30

struct CachedRecord<Value: Codable>: Codable {
    let value: Value
    let timestamp: TimeInterval
    let lifespan: TimeInterval
    
    // Before you're tempted to say, "Swift autosynthesizes initializers on structs, let's blow this away," let me tell you
    // this: I put this here as a fix to a compiler bug that overrode the timestamp on serialized records. Beware.
    init(value: Value, timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate, lifespan: TimeInterval) {
        self.value = value
        self.timestamp = timestamp
        self.lifespan = lifespan
    }
    
    var isExpired: Bool {
        return Date.timeIntervalSinceReferenceDate - self.timestamp > self.lifespan
    }
}

public protocol Defaults {
    func object(forKey defaultName: String) -> Any?
    
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: Defaults {
    
}

public final class Cache: Cachable {
    private let defaults: Defaults
    
    public init(defaults: Defaults) {
        self.defaults = defaults
    }
    
    public subscript<Key: RawRepresentable, Value: Codable>(_ key: Key) -> Value? where Key.RawValue == String {
        get {
            return self[key, defaultLifespan]
        }
        set {
            self[key, defaultLifespan] = newValue
        }
    }
    
    public subscript<Key: RawRepresentable, Value: Codable>(
        key: Key,
        lifespan: TimeInterval
    ) -> Value? where Key.RawValue == String {
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
                let cachedRecord = CachedRecord(value: newValue, lifespan: lifespan)
                
                let encoder = JSONEncoder()
                let encodedCachedRecord = try? encoder.encode(cachedRecord)
                
                self.defaults.set(encodedCachedRecord, forKey: key.rawValue)
            } else {
                self.defaults.set(nil, forKey: key.rawValue)
            }
        }
    }
}
