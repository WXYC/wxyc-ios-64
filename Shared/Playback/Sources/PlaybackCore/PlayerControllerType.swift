//
//  PlayerControllerType.swift
//  Playback
//
//  Enumeration of available PlaybackController implementations
//

import Foundation
import PostHog
import Caching

/// Available PlaybackController implementations
public enum PlayerControllerType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case radioPlayer = "RadioPlayer"
    case avAudioStreamer = "AVAudioStreamer"

    // MARK: - Persistence

    /// Uses app group UserDefaults so widget/intents can read the selected player type
    private static var defaults: UserDefaults { .wxyc }
    private static let userDefaultsKey = "debug.selectedPlayerControllerType"
    private static let manualSelectionKey = "debug.isPlayerControllerManuallySelected"
    
    // Feature Flag / Experiment Key
    private static let experimentKey = "experiment_player_controller"
    
    /// The default player controller type
    public static let defaultType: PlayerControllerType = .avAudioStreamer
    
    /// Loads the persisted player controller type, or returns default
    public static func loadPersisted() -> PlayerControllerType {
        // 1. Check if user manually selected a player in Debug View
        if defaults.bool(forKey: manualSelectionKey),
           let rawValue = defaults.string(forKey: userDefaultsKey),
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
        Self.defaults.set(rawValue, forKey: Self.userDefaultsKey)
        Self.defaults.set(true, forKey: Self.manualSelectionKey)
    }

    /// Clears the persisted player controller type
    public static func clearPersisted() {
        defaults.removeObject(forKey: userDefaultsKey)
        defaults.removeObject(forKey: manualSelectionKey)
    }
    
    // MARK: - Identifiable
    
    public var id: String { rawValue }
    
    // MARK: - Display
    
    public var displayName: String {
        switch self {
        case .radioPlayer:
            "RadioPlayer (AVPlayer)"
        case .avAudioStreamer:
            "AVAudioStreamer (AudioToolbox)"
        }
    }
    
    public var shortDescription: String {
        switch self {
        case .radioPlayer:
            "Uses AVPlayer for simple HTTP streaming"
        case .avAudioStreamer:
            "Uses URLSession + AudioToolbox for MP3 decoding"
        }
    }
}
