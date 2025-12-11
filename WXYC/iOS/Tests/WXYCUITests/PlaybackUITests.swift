//
//  PlaybackUITests.swift
//  WXYCUITests
//
//  UI tests to verify playback functionality doesn't crash
//

import XCTest

final class PlaybackUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    /// Test that tapping the play button doesn't crash the app
    /// This validates the fix for the EXC_BREAKPOINT crash in FrameFilterProcessor
    /// caused by actor isolation issues when the audio buffer callback is invoked
    /// from the realtime audio thread.
    @MainActor
    func testPlayButtonDoesNotCrash() throws {
        // Find the play/pause button
        let playButton = app.buttons["playPauseButton"]
        
        // Wait for the button to appear (app may need time to load)
        let exists = playButton.waitForExistence(timeout: 10)
        XCTAssertTrue(exists, "Play button should exist")
        
        // Tap to start playback
        playButton.tap()
        
        // Wait a moment for audio processing to begin
        // The crash would occur almost immediately when the frame filter
        // callback is first invoked from the realtime audio thread
        Thread.sleep(forTimeInterval: 2.0)
        
        // If we got here without crashing, the test passes
        // Verify the app is still running by checking the button still exists
        XCTAssertTrue(playButton.exists, "App should still be running after starting playback")
        
        // Tap again to stop playback
        playButton.tap()
        
        // Brief pause to ensure stop completes
        Thread.sleep(forTimeInterval: 0.5)
        
        XCTAssertTrue(playButton.exists, "App should still be running after stopping playback")
    }
    
    /// Test multiple play/pause cycles to ensure stability
    @MainActor
    func testMultiplePlayPauseCycles() throws {
        let playButton = app.buttons["playPauseButton"]
        
        let exists = playButton.waitForExistence(timeout: 10)
        XCTAssertTrue(exists, "Play button should exist")
        
        // Perform multiple play/pause cycles
        for cycle in 1...3 {
            // Start playback
            playButton.tap()
            Thread.sleep(forTimeInterval: 1.0)
            
            XCTAssertTrue(playButton.exists, "App should still be running after cycle \(cycle) play")
            
            // Stop playback
            playButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            
            XCTAssertTrue(playButton.exists, "App should still be running after cycle \(cycle) pause")
        }
    }
}
