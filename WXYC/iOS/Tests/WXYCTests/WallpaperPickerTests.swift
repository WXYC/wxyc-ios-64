//
//  WallpaperPickerTests.swift
//  WXYCTests
//
//  Tests for wallpaper picker state management and snapshot service.
//

import XCTest
@testable import WXYC
@testable import Wallpaper

// MARK: - WallpaperPickerState Tests

nonisolated final class WallpaperPickerStateTests: XCTestCase {

    func testInitialStateIsInactive() {
        let state = WallpaperPickerState()

        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.centeredWallpaperID, "")
        XCTAssertEqual(state.carouselIndex, 0)
        XCTAssertTrue(state.snapshots.isEmpty)
        XCTAssertFalse(state.isGeneratingSnapshots)
    }

    func testEnterSetsActiveState() {
        let state = WallpaperPickerState()
        let testWallpaperID = WallpaperRegistry.shared.wallpapers.first?.id ?? "test"

        state.enter(currentWallpaperID: testWallpaperID)

        XCTAssertTrue(state.isActive)
        XCTAssertEqual(state.centeredWallpaperID, testWallpaperID)
    }

    func testExitClearsActiveState() {
        let state = WallpaperPickerState()

        state.enter(currentWallpaperID: "test")
        XCTAssertTrue(state.isActive)

        state.exit()
        XCTAssertFalse(state.isActive)
    }

    func testUpdateCenteredWallpaper() {
        let state = WallpaperPickerState()
        let wallpapers = WallpaperRegistry.shared.wallpapers

        guard wallpapers.count >= 2 else {
            return // Skip if not enough wallpapers
        }

        state.updateCenteredWallpaper(forIndex: 1)

        XCTAssertEqual(state.carouselIndex, 1)
        XCTAssertEqual(state.centeredWallpaperID, wallpapers[1].id)
    }

    func testPrewarmedWallpaperIDs() {
        let state = WallpaperPickerState()
        let wallpapers = WallpaperRegistry.shared.wallpapers

        guard wallpapers.count >= 3 else {
            return // Skip if not enough wallpapers
        }

        // Set to middle of list
        state.updateCenteredWallpaper(forIndex: 1)

        let prewarmed = state.prewarmedWallpaperIDs

        // Should include center, left neighbor, and right neighbor
        XCTAssertTrue(prewarmed.contains(wallpapers[0].id))
        XCTAssertTrue(prewarmed.contains(wallpapers[1].id))
        XCTAssertTrue(prewarmed.contains(wallpapers[2].id))
    }

    func testStoreAndRetrieveSnapshot() {
        let state = WallpaperPickerState()

        // Create a mock snapshot with a 1x1 image
        let image = UIImage()

        let snapshot = WallpaperSnapshot(
            wallpaperID: "test-wallpaper",
            image: image,
            captureTime: 1.5
        )

        state.storeSnapshot(snapshot)

        let retrieved = state.snapshot(for: "test-wallpaper")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.wallpaperID, "test-wallpaper")
        XCTAssertEqual(retrieved?.captureTime, 1.5)
    }

    func testSnapshotForNonexistentWallpaperReturnsNil() {
        let state = WallpaperPickerState()

        let retrieved = state.snapshot(for: "nonexistent")
        XCTAssertNil(retrieved)
    }

    func testConfirmSelectionUpdatesConfiguration() {
        let state = WallpaperPickerState()
        let configuration = WallpaperConfiguration()

        let wallpapers = WallpaperRegistry.shared.wallpapers
        guard let firstWallpaper = wallpapers.first,
              let secondWallpaper = wallpapers.dropFirst().first else {
            return
        }

        // Set initial selection
        configuration.selectedWallpaperID = firstWallpaper.id

        // Enter picker and move to second wallpaper
        state.enter(currentWallpaperID: firstWallpaper.id)
        state.updateCenteredWallpaper(forIndex: 1)

        // Confirm selection
        state.confirmSelection(to: configuration)

        XCTAssertEqual(configuration.selectedWallpaperID, secondWallpaper.id)
    }
}

// MARK: - WallpaperRegistry Tests

nonisolated final class WallpaperRegistryTests: XCTestCase {

    func testRegistryContainsWallpapers() {
        let wallpapers = WallpaperRegistry.shared.wallpapers

        XCTAssertFalse(wallpapers.isEmpty)
    }

    func testWallpapersHaveUniqueIDs() {
        let wallpapers = WallpaperRegistry.shared.wallpapers
        let ids = Set(wallpapers.map(\.id))

        XCTAssertEqual(ids.count, wallpapers.count)
    }

    func testWallpapersHaveDisplayNames() {
        for wallpaper in WallpaperRegistry.shared.wallpapers {
            XCTAssertFalse(wallpaper.displayName.isEmpty)
        }
    }
}

// MARK: - WallpaperSnapshot Tests

nonisolated final class WallpaperSnapshotTests: XCTestCase {

    func testSnapshotStoresData() {
        let image = UIImage()

        let snapshot = WallpaperSnapshot(
            wallpaperID: "my-wallpaper",
            image: image,
            captureTime: 2.5
        )

        XCTAssertEqual(snapshot.wallpaperID, "my-wallpaper")
        XCTAssertEqual(snapshot.captureTime, 2.5)
    }
}
