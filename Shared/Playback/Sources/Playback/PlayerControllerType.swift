//
//  PlayerControllerType.swift
//  Playback
//
//  Enumeration of available PlaybackController implementations
//

import Foundation
import PostHog

/// Available PlaybackController implementations
public enum PlayerControllerType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case radioPlayer = "RadioPlayer"
    case audioPlayer = "AudioPlayer"
    case avAudioStreamer = "AVAudioStreamer"
    case miniMP3Streamer = "MiniMP3Streamer"
    
    // MARK: - Persistence
    
    private static let userDefaultsKey = "debug.selectedPlayerControllerType"
    private static let manualSelectionKey = "debug.isPlayerControllerManuallySelected"
    
    // Feature Flag / Experiment Key
    private static let experimentKey = "experiment_player_controller"
    
    /// The default player controller type
    public static let defaultType: PlayerControllerType = .audioPlayer
    
    /// Loads the persisted player controller type, or returns default
    public static func loadPersisted() -> PlayerControllerType {
        // 1. Check if user manually selected a player in Debug View
        if UserDefaults.standard.bool(forKey: manualSelectionKey),
           let rawValue = UserDefaults.standard.string(forKey: userDefaultsKey),
           let type = PlayerControllerType(rawValue: rawValue) {
            return type
        }
        
        // 2. Check PostHog Experiment (Feature Flag)
        // This returns the Variant Key (e.g. "radioPlayer", "avAudioStreamer")
        if let variant = PostHogSDK.shared.getFeatureFlag(experimentKey) as? String,
           let type = PlayerControllerType(rawValue: variant) {
            return type
        }
        
        // 3. Fallback to default
        return defaultType
    }
    
    /// Persists the selected player controller type
    public func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.userDefaultsKey)
        UserDefaults.standard.set(true, forKey: Self.manualSelectionKey)
    }
    
    /// Clears the persisted player controller type
    public static func clearPersisted() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        UserDefaults.standard.removeObject(forKey: manualSelectionKey)
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
            return "AVAudioStreamer (AudioToolbox)"
        case .miniMP3Streamer:
            return "MiniMP3Streamer (MiniMP3)"
        }
    }
    
    public var shortDescription: String {
        switch self {
        case .radioPlayer:
            return "Uses AVPlayer for simple HTTP streaming"
        case .audioPlayer:
            return "Uses AudioStreaming library with custom buffering"
        case .avAudioStreamer:
            return "Uses URLSession + AudioToolbox for MP3 decoding"
        case .miniMP3Streamer:
            return "Uses URLSession + MiniMP3 (pure C decoder, works on watchOS)"
        }
    }
}

