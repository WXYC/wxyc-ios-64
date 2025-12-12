import Foundation

public struct StallEvent: Sendable {
    public let playerType: PlayerControllerType
    public let timestamp: Date
    public let playbackDuration: TimeInterval  // How long was it playing before stall?
    public let reason: StallReason?
    
    public enum StallReason: String, Sendable {
        case bufferUnderrun = "buffer_underrun"
        case networkError = "network_error"
        case unknown = "unknown"
    }
    
    public init(playerType: PlayerControllerType, timestamp: Date, playbackDuration: TimeInterval, reason: StallReason?) {
        self.playerType = playerType
        self.timestamp = timestamp
        self.playbackDuration = playbackDuration
        self.reason = reason
    }
    
    public var properties: [String: Any] {
        [
            "player_type": playerType.rawValue,
            "playback_duration": playbackDuration,
            "reason": reason?.rawValue ?? "unknown",
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
    }
}
