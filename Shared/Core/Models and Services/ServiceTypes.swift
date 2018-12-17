import Foundation

public enum Result<T> {
    case success(T)
    case error(Error)
}

public extension TimeInterval {
    static let distantFuture = Date.distantFuture.timeIntervalSince1970
}

/// `NowPlayingService` will throw one of these errors, depending
enum ServiceErrors: String, LocalizedError {
    case noResults
    case noNewData
    case noCachedResult
}

protocol WebSession {
    func request(url: URL) -> Future<Data>
}
