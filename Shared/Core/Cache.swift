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

protocol Defaults {
    func object(forKey defaultName: String) -> Any?
    
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: Defaults {
    
}

enum CacheKey: String {
    case playcut
    case playlist
    case artwork
}

public final class Cache {
    public static var WXYC: Cache {
        return Cache(defaults: UserDefaults(suiteName: "org.wxyc.apps")!)
    }
    
    private let defaults: Defaults
    
    init(defaults: Defaults) {
        self.defaults = defaults
    }

    public subscript<Key: Codable, Value: Codable>(_ key: Key) -> Future<Value> {
        get {
            guard let json = try? key.JSONEncode() else {
                return Promise(error: ServiceErrors.noCachedResult)
            }
            
            guard let value: Value = self[json, defaultLifespan] else {
                return Promise(error: ServiceErrors.noCachedResult)
            }
            
            return Promise(value: value)
        }
    }
    
    public subscript<Key: Codable, Value: Codable>(_ key: Key) -> Value? {
        get {
            guard let json = try? key.JSONEncode() else {
                return nil
            }
            
            guard let value: Value = self[json, defaultLifespan] else {
                return nil
            }
            
            return value
        }
        set {
            guard let json = try? key.JSONEncode() else {
                return
            }
            
            self[json] = newValue
        }
    }
    
    public subscript<Key: RawRepresentable, Value: Codable>(_ key: Key) -> Value? where Key.RawValue == String {
        get {
            return self[key.rawValue, defaultLifespan]
        }
        set {
            self[key.rawValue, defaultLifespan] = newValue
        }
    }
    
    private subscript<Value: Codable>(
        key: String,
        lifespan: TimeInterval
    ) -> Value? {
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
            if let newValue = newValue {
                let cachedRecord = CachedRecord(value: newValue, lifespan: lifespan)
                
                let encoder = JSONEncoder()
                let encodedCachedRecord = try? encoder.encode(cachedRecord)
                
                self.defaults.set(encodedCachedRecord, forKey: key)
            } else {
                self.defaults.set(nil, forKey: key)
            }
        }
    }
}

private let encoder = JSONEncoder()
private let decoder = JSONDecoder()

extension Encodable {
    func JSONEncode() throws -> String {
        let data = try encoder.encode(self)
        let string = try decoder.decode(String.self, from: data)
        return string
    }
}
