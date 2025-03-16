import Foundation

public extension TimeInterval {
    static let distantFuture = Date.distantFuture.timeIntervalSince1970
    static let oneDay = 60.0 * 60.0 * 24.0
}

/// `NowPlayingService` will throw one of these errors, depending
enum ServiceError: String, LocalizedError, Codable {
    case noResults
    case noNewData
    case noCachedResult
}

protocol WebSession: Sendable {
    func data(from url: URL) async throws -> Data
}
