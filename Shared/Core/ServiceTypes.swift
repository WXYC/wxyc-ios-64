import Foundation

public enum Result<T> {
    case success(T)
    case error(Error)
}

/// `NowPlayingService` will throw one of these errors, depending
enum ServiceErrors: Error {
    case noResults
    case noNewData
    case noCachedResult
}

protocol WebSession {
    func request(url: URL) -> Future<Data>
}

public protocol Cachable: AnyObject {
    subscript<Key: RawRepresentable, Value: Codable>(key: Key) -> Value? where Key.RawValue == String { get set }
}

extension UserDefaults: Cachable {
    public subscript<Key, Value>(key: Key) -> Value? where Key : RawRepresentable, Value : Decodable, Value : Encodable, Key.RawValue == String {
        get {
            return self.value(forKey: key.rawValue) as? Value
        }
        set {
            self.set(newValue, forKey: key.rawValue)
        }
    }
}
