//
//  PlayerControllerType.swift
//  Playback
//
//  Enumeration of available PlaybackController implementations
//
//  Created by Jake Bromberg on 12/07/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Analytics
import Caching
import Foundation

/// Available PlaybackController implementations
public enum PlayerControllerType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case radioPlayer = "RadioPlayer"
    case mp3Streamer = "MP3Streamer"

    // MARK: - Persistence

    /// Uses app group UserDefaults so widget/intents can read the selected player type
    private static var defaults: UserDefaults { .wxyc }
    private static let userDefaultsKey = "debug.selectedPlayerControllerType"
    private static let manualSelectionKey = "debug.isPlayerControllerManuallySelected"
    
    // Feature Flag / Experiment Key
    private static let experimentKey = "experiment_player_controller"
    
    /// The default player controller type
    public static let defaultType: PlayerControllerType = .mp3Streamer
    
    /// Loads the persisted player controller type, or returns default
    public static func loadPersisted() -> PlayerControllerType {
        loadPersisted(featureFlagProvider: PostHogFeatureFlagProvider.shared)
    }

    /// Loads the persisted player controller type with injectable feature flag provider.
    public static func loadPersisted(featureFlagProvider: FeatureFlagProvider) -> PlayerControllerType {
        loadPersisted(featureFlagProvider: featureFlagProvider, defaults: defaults)
    }

    /// Internal method with full dependency injection for testing.
    static func loadPersisted(
        featureFlagProvider: FeatureFlagProvider,
        defaults: DefaultsStorage
    ) -> PlayerControllerType {
        // 1. Check if user manually selected a player in Debug View
        if defaults.bool(forKey: manualSelectionKey),
           let rawValue = defaults.string(forKey: userDefaultsKey),
           let type = PlayerControllerType(rawValue: rawValue) {
            return type
        }

        // 2. Check feature flag experiment
        if let variant = featureFlagProvider.getFeatureFlag(experimentKey) as? String,
           let type = PlayerControllerType(rawValue: variant) {
            return type
        }

        // 3. Fallback to default
        return defaultType
    }
    
    /// Persists the selected player controller type
    public func persist() {
        persist(to: Self.defaults)
    }

    /// Persists the selected player controller type to the specified defaults.
    func persist(to defaults: DefaultsStorage) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
        defaults.set(true, forKey: Self.manualSelectionKey)
    }

    /// Clears the persisted player controller type
    public static func clearPersisted() {
        clearPersisted(from: defaults)
    }

    /// Clears the persisted player controller type from the specified defaults.
    static func clearPersisted(from defaults: DefaultsStorage) {
        defaults.removeObject(forKey: userDefaultsKey)
        defaults.removeObject(forKey: manualSelectionKey)
    }
    
    // MARK: - Identifiable
    
    public var id: String { rawValue }
}
