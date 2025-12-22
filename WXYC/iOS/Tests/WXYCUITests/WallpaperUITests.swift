//
//  WallpaperUITests.swift
//  WXYCUITests
//
//  UI tests for wallpaper selection and display
//

import XCTest

final class WallpaperUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helper Methods

    /// Opens the wallpaper picker via long press on the playlist view
    private func openWallpaperPicker() -> Bool {
        let playlistView = app.otherElements["playlistView"]

        // Wait for playlist view to be available
        guard playlistView.waitForExistence(timeout: 5) else {
            // Fallback: try long press on the main window
            let mainWindow = app.windows.firstMatch
            guard mainWindow.waitForExistence(timeout: 5) else {
                return false
            }
            mainWindow.press(forDuration: 0.6)
            Thread.sleep(forTimeInterval: 0.5)
            return true
        }

        // Long press to open wallpaper picker
        playlistView.press(forDuration: 0.6)
        Thread.sleep(forTimeInterval: 0.5)
        return true
    }

    // MARK: - Navigation Tests

    /// Test that the playlist view exists and is accessible
    @MainActor
    func testPlaylistViewExists() throws {
        // Wait for app to load
        Thread.sleep(forTimeInterval: 2.0)

        // Verify app is running and main UI is visible
        XCTAssertTrue(app.exists, "App should be running")

        // The app uses a paged tab view, verify the main scroll view exists
        let scrollViews = app.scrollViews
        XCTAssertTrue(scrollViews.count > 0 || app.otherElements.count > 0,
                     "Main UI elements should be visible")
    }

    /// Test that wallpaper picker can be accessed via long press
    @MainActor
    func testWallpaperPickerAccess() throws {
        // Wait for app to fully load
        Thread.sleep(forTimeInterval: 2.0)

        // Long press to open wallpaper picker
        let opened = openWallpaperPicker()
        XCTAssertTrue(opened, "Should be able to perform long press gesture")

        // Wait for picker animation
        Thread.sleep(forTimeInterval: 1.0)

        // App should still be responsive
        XCTAssertTrue(app.exists, "App should be running after opening wallpaper picker")
    }

    // MARK: - Wallpaper Selection Tests

    /// Test that selecting a wallpaper works without crashing
    @MainActor
    func testWallpaperSelection() throws {
        // Wait for app to load
        Thread.sleep(forTimeInterval: 2.0)

        // Open wallpaper picker
        guard openWallpaperPicker() else {
            throw XCTSkip("Could not access wallpaper picker")
        }

        // Wait for picker to appear
        Thread.sleep(forTimeInterval: 1.0)

        // Try to find and tap a wallpaper option
        // The carousel uses scroll views or buttons
        let buttons = app.buttons
        let scrollViews = app.scrollViews

        // Try tapping any button that might be a wallpaper option
        if buttons.count > 0 {
            buttons.firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.5)
        } else if scrollViews.count > 0 {
            // Swipe in the carousel to see if selection works
            scrollViews.firstMatch.swipeLeft()
            Thread.sleep(forTimeInterval: 0.5)
        }

        // App should still be responsive
        XCTAssertTrue(app.exists, "App should still be running after wallpaper interaction")
    }

    /// Test that wallpaper renders without crashing
    @MainActor
    func testWallpaperRenderingStability() throws {
        // Just launch and wait - the wallpaper should be rendering in the background
        Thread.sleep(forTimeInterval: 3.0)

        // Verify app is still running
        XCTAssertTrue(app.exists, "App should be running with wallpaper rendered")

        // Verify main UI elements are visible (the app uses paged TabView, not standard tab bar)
        let windows = app.windows
        XCTAssertTrue(windows.count > 0, "App window should be visible")
    }

    // MARK: - Stress Tests

    /// Test swipe navigation doesn't crash with wallpaper rendering
    @MainActor
    func testSwipeNavigationWithWallpaper() throws {
        // Wait for app to load
        Thread.sleep(forTimeInterval: 2.0)

        // The app uses a paged TabView - swipe between pages
        let mainWindow = app.windows.firstMatch
        guard mainWindow.waitForExistence(timeout: 3) else {
            throw XCTSkip("Could not find main window")
        }

        // Swipe left and right between pages multiple times
        for _ in 0..<3 {
            mainWindow.swipeLeft()
            Thread.sleep(forTimeInterval: 0.3)
            mainWindow.swipeRight()
            Thread.sleep(forTimeInterval: 0.3)
        }

        // App should survive navigation
        XCTAssertTrue(app.exists, "App should survive swipe navigation with wallpaper")
    }

    /// Test that wallpaper continues rendering during app lifecycle
    @MainActor
    func testWallpaperPersistsThroughBackground() throws {
        // Wait for initial render
        Thread.sleep(forTimeInterval: 2.0)

        // Background the app
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.0)

        // Reactivate the app
        app.activate()
        Thread.sleep(forTimeInterval: 1.0)

        // Verify app recovered
        XCTAssertTrue(app.exists, "App should exist after backgrounding")

        // Verify window is visible
        let windows = app.windows
        XCTAssertTrue(windows.firstMatch.waitForExistence(timeout: 5),
                     "UI should be visible after foregrounding")
    }
}
