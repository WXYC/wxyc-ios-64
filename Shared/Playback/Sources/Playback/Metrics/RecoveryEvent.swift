import Foundation

public struct RecoveryEvent: Sendable {
    public let playerType: PlayerControllerType
    public let successful: Bool
    public let attemptCount: Int
    public let stallDuration: TimeInterval  // Time from stall to recovery
    public let recoveryMethod: RecoveryMethod
    
    public enum RecoveryMethod: String, Sendable {
        case automaticReconnect = "automatic_reconnect"  // Protocol-level reconnect (HTTP, FFmpeg, etc.)
        case retryWithBackoff = "retry_with_backoff"     // Application-level retry with delays
        case bufferRefill = "buffer_refill"              // Buffer replenished naturally
        case streamRestart = "stream_restart"            // Complete stream teardown and restart
        case userInitiated = "user_initiated"            // User manually triggered retry
    }
    
    public init(playerType: PlayerControllerType, successful: Bool, attemptCount: Int, stallDuration: TimeInterval, recoveryMethod: RecoveryMethod) {
        self.playerType = playerType
        self.successful = successful
        self.attemptCount = attemptCount
        self.stallDuration = stallDuration
        self.recoveryMethod = recoveryMethod
    }
    
    public var properties: [String: Any] {
        [
            "player_type": playerType.rawValue,
            "successful": successful,
            "attempt_count": attemptCount,
            "stall_duration": stallDuration,
            "recovery_method": recoveryMethod.rawValue
        ]
    }
}
