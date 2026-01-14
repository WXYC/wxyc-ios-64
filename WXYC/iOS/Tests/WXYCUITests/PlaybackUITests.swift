//
//  PlaybackUITests.swift
//  WXYC
//
//  UI tests to verify playback functionality doesn't crash
//
//  Created by Jake Bromberg on 12/01/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import XCTest

@Suite("Playback UI Tests", .serialized)
@MainActor
struct PlaybackUITests {

    let app = XCUIApplication()

    init() {
        app.launch()
    }

    /// Test that tapping the play button doesn't crash the app.
    /// This validates the fix for the EXC_BREAKPOINT crash in FrameFilterProcessor
    /// caused by actor isolation issues when the audio buffer callback is invoked
    /// from the realtime audio thread.
    @Test("Play button doesn't crash")
    func playButtonDoesNotCrash() async throws {
        let playButton = app.buttons["playPauseButton"]

        // Wait for the button to appear
        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")
        
        // Tap to start playback
        playButton.tap()

        // Wait for button to remain responsive after audio processing begins.
        // The crash would occur almost immediately when the frame filter
        // callback is first invoked from the realtime audio thread.
        try await waitUntil(playButton, is: .exists, .hittable)

        // If we got here without crashing, verify the app is still running
        #expect(playButton.exists, "App should still be running after starting playback")

        // Tap again to stop playback
        playButton.tap()

        // Wait for stop to complete
        try await waitUntil(playButton, is: .exists, .hittable)

        #expect(playButton.exists, "App should still be running after stopping playback")
    }

    /// Test multiple play/pause cycles to ensure stability
    @Test("Multiple play/pause cycles")
    func multiplePlayPauseCycles() async throws {
        let playButton = app.buttons["playPauseButton"]
    
        let exists = playButton.waitForExistence(timeout: 10)
        #expect(exists, "Play button should exist")

        // Perform multiple play/pause cycles
        for cycle in 1...3 {
            // Start playback
            playButton.tap()
            try await waitUntil(playButton, is: .exists, .hittable)

            #expect(playButton.exists, "App should still be running after cycle \(cycle) play")

            // Stop playback
            playButton.tap()
            try await waitUntil(playButton, is: .exists, .hittable)

            #expect(playButton.exists, "App should still be running after cycle \(cycle) pause")
        }
    }
}
