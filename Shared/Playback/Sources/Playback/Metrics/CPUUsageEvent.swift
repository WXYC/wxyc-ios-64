import Foundation

public struct CPUUsageEvent: Sendable {
    public let playerType: PlayerControllerType
    public let cpuUsage: Double
    public let timestamp: Date
    
    public init(playerType: PlayerControllerType, cpuUsage: Double, timestamp: Date = Date()) {
        self.playerType = playerType
        self.cpuUsage = cpuUsage
        self.timestamp = timestamp
    }
    
    public var properties: [String: Any] {
        return [
            "player_type": playerType.rawValue,
            "cpu_usage": cpuUsage,
            "timestamp": timestamp.timeIntervalSince1970
        ]
    }
}
