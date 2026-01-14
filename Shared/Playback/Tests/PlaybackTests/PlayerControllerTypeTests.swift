//
//  PlayerControllerTypeTests.swift
//  Playback
//
//  Created by Jake Bromberg on 12/11/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import Foundation
import PostHog
@testable import Playback

@Suite("PlayerControllerType Experiment Tests")
@MainActor
struct PlayerControllerTypeTests {
    
    init() {
        // Reset state before each test
        PlayerControllerType.clearPersisted()
        // We can't easily reset PostHogSDK singleton state, but we can rely on our Mock injection 
        // OR simply set feature flag mock values if the SDK allows.
        // PostHogSDK is a singleton Objective-C wrapper. 
        // We might need to mock getFeatureFlag. 
        // Looking at AnalyticsService, PostHogSDK is the class.
        // We cannot easily swizzle or mock the Singleton instance unless we have an interface for it.
        // However, `PlayerControllerType` calls `PostHogSDK.shared`.
        
        // This makes unit testing the "Experiment" part hard without a wrapper.
        // But we CAN test the manual override logic which relies on UserDefaults.
    }
    
    @Test("Default type is returned when no persistence or global state")
    func defaultsToAudioPlayer() {
        PlayerControllerType.clearPersisted()
        // Assuming no feature flag set in global state
        // This test might be flaky if integration tests set flags. 
        // But for local unit testing it should be fine.
        #expect(PlayerControllerType.loadPersisted() == .defaultType)
    }
        
    @Test("Manual selection overrides everything")
    func manualSelectionOverrides() {
        PlayerControllerType.clearPersisted()
    
        // Simulate user selection
        var type = PlayerControllerType.mp3Streamer
        type.persist() // This sets manual flag to true
        
        let loaded = PlayerControllerType.loadPersisted()
        #expect(loaded == .mp3Streamer)
    }
    
    @Test("Clearing persistence removes manual flag")
    func clearPersistenceResets() {
        // Setup
        var type = PlayerControllerType.radioPlayer
        type.persist()
        #expect(PlayerControllerType.loadPersisted() == .radioPlayer)

        // Act
        PlayerControllerType.clearPersisted()

        // Assert
        #expect(PlayerControllerType.loadPersisted() == .defaultType)
    }
}
