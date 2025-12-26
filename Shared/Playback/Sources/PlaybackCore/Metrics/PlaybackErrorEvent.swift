import Foundation

public struct PlaybackErrorEvent: Sendable {
    public let playerType: PlayerControllerType
    public let errorType: ErrorType
    public let errorDescription: String
    public let context: String
    public let isRecoverable: Bool
    
    public enum ErrorType: String, Sendable {
        case networkError = "network_error"
        case decodingError = "decoding_error"
        case audioSessionError = "audio_session_error"
        case engineError = "engine_error"
        case openFailed = "open_failed"
        case unknown = "unknown"
    }
    
    public init(playerType: PlayerControllerType, errorType: ErrorType, errorDescription: String, context: String, isRecoverable: Bool) {
        self.playerType = playerType
        self.errorType = errorType
        self.errorDescription = errorDescription
        self.context = context
        self.isRecoverable = isRecoverable
    }
    
    public var properties: [String: Any] {
        [
            "player_type": playerType.rawValue,
            "error_type": errorType.rawValue,
            "error_description": errorDescription,
            "context": context,
            "is_recoverable": isRecoverable
        ]
    }
}
