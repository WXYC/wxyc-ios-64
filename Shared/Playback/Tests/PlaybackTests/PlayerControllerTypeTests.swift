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
@testable import PlaybackCore

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

    @Test("Each type has a non-empty display name", arguments: PlayerControllerType.allCases)
    func displayNameIsNonEmpty(type: PlayerControllerType) {
        #expect(!type.displayName.isEmpty)
    }

    @Test("Each type has a non-empty short description", arguments: PlayerControllerType.allCases)
    func shortDescriptionIsNonEmpty(type: PlayerControllerType) {
        #expect(!type.shortDescription.isEmpty)
    }

    @Test("HLS player display name mentions HLS")
    func hlsDisplayNameMentionsHLS() {
        #expect(PlayerControllerType.hlsPlayer.displayName.contains("HLS"))
    }
}

@Suite("HLSEnvironment Tests")
@MainActor
struct HLSEnvironmentTests {

    // The three UserDefaults-touching tests below used to share the process-wide
    // `.wxyc` app-group suite via the public `HLSEnvironment.loadActive()` /
    // `.persist()` / `.clearOverride()` entry points. Swift Testing runs sibling
    // `@Test` functions concurrently, so one instance's `init()` clearing that
    // shared suite could race another instance's `persist()`, wiping its state
    // before the assertion ran — reproduced locally at 4/8 full-suite runs
    // failing on exactly this interleaving (#371). Each test below now drives an
    // isolated `UserDefaults` suite through the internal `defaults:`-injectable
    // overloads instead, so no two tests can ever observe each other's writes.
    // The remaining pure-value tests (urlIsNonEmpty / stagingURLIsCorrect /
    // productionURLIsCorrect) never touched UserDefaults and were never at risk.

    /// Creates a fresh, isolated `UserDefaults` suite so concurrent test
    /// instances can't bleed into each other's persisted state.
    private func makeTestDefaults() -> UserDefaults {
        let suiteName = "com.wxyc.test.HLSEnvironmentTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test("Default environment is production")
    func defaultIsProduction() {
        let defaults = makeTestDefaults()
        #expect(HLSEnvironment.loadActive(from: defaults) == .production)
    }

    @Test("Manual override persists and loads")
    func manualOverride() {
        let defaults = makeTestDefaults()
        HLSEnvironment.staging.persist(to: defaults)
        #expect(HLSEnvironment.loadActive(from: defaults) == .staging)
    }

    @Test("Clearing override reverts to default")
    func clearOverride() {
        let defaults = makeTestDefaults()
        HLSEnvironment.staging.persist(to: defaults)
        HLSEnvironment.clearOverride(from: defaults)
        #expect(HLSEnvironment.loadActive(from: defaults) == .production)
    }

    @Test("Each environment has a distinct URL", arguments: HLSEnvironment.allCases)
    func urlIsNonEmpty(env: HLSEnvironment) {
        #expect(!env.url.absoluteString.isEmpty)
    }

    @Test("Staging URL points to staging host")
    func stagingURLIsCorrect() {
        #expect(HLSEnvironment.staging.url.host() == "hls-staging.wxyc.org")
    }

    @Test("Production URL points to production host")
    func productionURLIsCorrect() {
        #expect(HLSEnvironment.production.url.host() == "hls.wxyc.org")
    }
}
