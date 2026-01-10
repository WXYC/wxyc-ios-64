import Foundation

public struct CacheMetadata: Codable, Sendable {
    public let timestamp: TimeInterval
    public let lifespan: TimeInterval

    public init(timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate, lifespan: TimeInterval) {
        self.timestamp = timestamp
        self.lifespan = lifespan
    }

    /// Check if expired relative to a given time.
    public func isExpired(at currentTime: TimeInterval) -> Bool {
        currentTime - timestamp > lifespan
    }

    /// Check if expired using the system clock. Prefer `isExpired(at:)` for testability.
    public var isExpired: Bool {
        isExpired(at: Date.timeIntervalSinceReferenceDate)
    }
}
