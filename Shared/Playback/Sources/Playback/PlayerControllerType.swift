//
//  PlayerControllerType.swift
//  Playback
//
//  Enumeration of available PlaybackController implementations
//

import Foundation

/// Available PlaybackController implementations
public enum PlayerControllerType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case radioPlayer = "RadioPlayer"
    case audioPlayer = "AudioPlayer"
    case avAudioStreamer = "AVAudioStreamer"
    case miniMP3Streamer = "MiniMP3Streamer"
    #if os(iOS) || os(watchOS)
    case ffmpegAudio = "FFmpegAudio"
    #endif
    
    // MARK: - Persistence
    
    private static let userDefaultsKey = "debug.selectedPlayerControllerType"
    
    /// The default player controller type
    public static let defaultType: PlayerControllerType = .audioPlayer
    
    /// Loads the persisted player controller type, or returns default
    public static func loadPersisted() -> PlayerControllerType {
        guard let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
              let type = PlayerControllerType(rawValue: rawValue) else {
            return defaultType
        }
        return type
    }
    
    /// Persists the selected player controller type
    public func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
    }
    
    /// Clears the persisted player controller type
    public static func clearPersisted() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
    
    // MARK: - Identifiable
    
    public var id: String { rawValue }
    
    // MARK: - Display
    
    public var displayName: String {
        switch self {
        case .radioPlayer:
            return "RadioPlayer (AVPlayer)"
        case .audioPlayer:
            return "AudioPlayer (AudioStreaming)"
        case .avAudioStreamer:
            return "AVAudioStreamer (NIO + AudioToolbox)"
        case .miniMP3Streamer:
            return "MiniMP3Streamer (NIO + MiniMP3)"
        case .ffmpegAudio:
            return "FFmpeg (FFmpegAudio)"
        }
    }
    
    public var shortDescription: String {
        switch self {
        case .radioPlayer:
            return "Uses AVPlayer for simple HTTP streaming"
        case .audioPlayer:
            return "Uses AudioStreaming library with custom buffering"
        case .avAudioStreamer:
            return "Uses Swift NIO + AudioToolbox for MP3 decoding"
        case .miniMP3Streamer:
            return "Uses Swift NIO + MiniMP3 (pure C decoder, works on watchOS)"
        case .ffmpegAudio:
            return "Uses FFmpeg-based decoder with AVAudioEngine output"
        }
    }
}

