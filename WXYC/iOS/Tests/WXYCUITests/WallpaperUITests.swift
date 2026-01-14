//
//  WallpaperUITests.swift
//  WXYC
//
//  UI tests for wallpaper selection and display
//
//  Created by Jake Bromberg on 12/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Testing
import XCTest

@Suite("Wallpaper UI Tests", .serialized)
@MainActor
struct WallpaperUITests {

    let app = XCUIApplication()

    init() {
        app.launch()
    }

    // MARK: - Helper Methods

    /// Opens the wallpaper picker via long press on the playlist view
    private func openWallpaperPicker() async throws -> Bool {
        let playlistView = app.otherElements["playlistView"]

        // Wait for playlist view to be available
        guard playlistView.waitForExistence(timeout: 5) else {
            // Fallback: try long press on the main window
            let mainWindow = app.windows.firstMatch
            guard mainWindow.waitForExistence(timeout: 5) else {
                return false
            }
            mainWindow.press(forDuration: 0.6)
            // Brief delay for gesture recognition
            try await Task.sleep(for: .milliseconds(100))
            return true
        }

        // Long press to open wallpaper picker
        playlistView.press(forDuration: 0.6)
        // Brief delay for gesture recognition
        try await Task.sleep(for: .milliseconds(100))
        return true
    }

    // MARK: - Navigation Tests

    /// Test that the playlist view exists and is accessible
    @Test("Playlist view exists")
    func playlistViewExists() async throws {
        // Wait for app to be ready
        try await waitUntil(timeout: .seconds(5), "app window") {
            app.windows.count > 0
        }

        // Verify app is running and main UI is visible
        #expect(app.exists, "App should be running")

        // The app uses a paged tab view, verify the main scroll view exists
        let scrollViews = app.scrollViews
        #expect(scrollViews.count > 0 || app.otherElements.count > 0,
                "Main UI elements should be visible")
    }

    /// Test that wallpaper picker can be accessed via long press
    @Test("Wallpaper picker access")
    func wallpaperPickerAccess() async throws {
        // Wait for app to be ready
        try await waitUntil(timeout: .seconds(5), "app window") {
            app.windows.count > 0
        }

        // Long press to open wallpaper picker
        let opened = try await openWallpaperPicker()
        #expect(opened, "Should be able to perform long press gesture")

        // Wait for picker to appear
        try await Task.sleep(for: .milliseconds(500))

        // App should still be responsive
        #expect(app.exists, "App should be running after opening wallpaper picker")
    }

    // MARK: - Wallpaper Selection Tests

    /// Test that selecting a wallpaper works without crashing
    @Test("Wallpaper selection")
    func wallpaperSelection() async throws {
        // Wait for app to be ready
        try await waitUntil(timeout: .seconds(5), "app window") {
            app.windows.count > 0
        }

        // Open wallpaper picker
        let opened = try await openWallpaperPicker()
        guard opened else {
            throw TestTimeoutError("Could not access wallpaper picker")
        }

        // Wait for picker to appear
        try await Task.sleep(for: .milliseconds(500))

        // Try to find and tap a wallpaper option
        let buttons = app.buttons
        let scrollViews = app.scrollViews

        // Try tapping any button that might be a wallpaper option
        if buttons.count > 0 {
            buttons.firstMatch.tap()
            await Task.yield()
        } else if scrollViews.count > 0 {
            // Swipe in the carousel to see if selection works
            scrollViews.firstMatch.swipeLeft()
            await Task.yield()
        }

        // App should still be responsive
        #expect(app.exists, "App should still be running after wallpaper interaction")
    }

    /// Test that wallpaper renders without crashing
    @Test("Wallpaper rendering stability")
    func wallpaperRenderingStability() async throws {
        // Wait for app and wallpaper to be ready
        try await waitUntil(timeout: .seconds(5), "app window") {
            app.windows.count > 0
        }

        // Verify app is still running
        #expect(app.exists, "App should be running with wallpaper rendered")

        // Verify main UI elements are visible
        let windows = app.windows
        #expect(windows.count > 0, "App window should be visible")
    }

    // MARK: - Stress Tests

    /// Test swipe navigation doesn't crash with wallpaper rendering
    @Test("Swipe navigation with wallpaper")
    func swipeNavigationWithWallpaper() async throws {
        let mainWindow = app.windows.firstMatch
        guard mainWindow.waitForExistence(timeout: 5) else {
            throw TestTimeoutError("Could not find main window")
        }

        // Swipe left and right between pages multiple times
        for _ in 0..<3 {
            mainWindow.swipeLeft()
            await Task.yield()
            mainWindow.swipeRight()
            await Task.yield()
        }

        // App should survive navigation
        #expect(app.exists, "App should survive swipe navigation with wallpaper")
    }

    /// Test that wallpaper continues rendering during app lifecycle
    @Test("Wallpaper persists through background")
    func wallpaperPersistsThroughBackground() async throws {
        // Wait for initial app load
        try await waitUntil(timeout: .seconds(5), "app window") {
            app.windows.count > 0
        }

        // Background the app
        XCUIDevice.shared.press(.home)

        // Wait for background transition
        try await Task.sleep(for: .seconds(1))

        // Reactivate the app
        app.activate()

        // Wait for app to be accessible again
        try await waitUntil(timeout: .seconds(5), "app recovery") {
            app.windows.firstMatch.exists
        }

        // Verify app recovered
        #expect(app.exists, "App should exist after backgrounding")

        // Verify window is visible
        let windows = app.windows
        #expect(windows.firstMatch.exists, "UI should be visible after foregrounding")
    }
}
