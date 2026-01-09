import Foundation

struct CacheMetadata: Codable, Sendable {
    let timestamp: TimeInterval
    let lifespan: TimeInterval

    init(timestamp: TimeInterval = Date.timeIntervalSinceReferenceDate, lifespan: TimeInterval) {
        self.timestamp = timestamp
        self.lifespan = lifespan
    }

    /// Check if expired relative to a given time.
    func isExpired(at currentTime: TimeInterval) -> Bool {
        currentTime - timestamp > lifespan
    }

    /// Check if expired using the system clock. Prefer `isExpired(at:)` for testability.
    var isExpired: Bool {
        isExpired(at: Date.timeIntervalSinceReferenceDate)
    }
}
