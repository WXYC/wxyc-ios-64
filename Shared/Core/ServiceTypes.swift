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

protocol Cachable: AnyObject {
    subscript<Key: RawRepresentable, Value: Codable>(key: Key) -> Value? where Key.RawValue == String { get set }
}
