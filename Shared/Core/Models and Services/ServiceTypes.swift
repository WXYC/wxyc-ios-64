import Foundation

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
    func data(from url: URL) async throws -> Data
}
