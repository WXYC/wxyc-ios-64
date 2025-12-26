//
//  WallpaperPickerTests.swift
//  WXYCTests
//
//  Tests for wallpaper picker state management and snapshot service.
//

import Testing
import UIKit
@testable import WXYC
@testable import Wallpaper

// MARK: - WallpaperPickerState Tests

@Suite("WallpaperPickerState Tests")
@MainActor
struct WallpaperPickerStateTests {

    @Test("Initial state is inactive")
    func initialStateIsInactive() {
        let state = WallpaperPickerState()

        #expect(state.isActive == false)
        #expect(state.centeredWallpaperID == "")
        #expect(state.carouselIndex == 0)
        #expect(state.snapshots.isEmpty)
        #expect(state.isGeneratingSnapshots == false)
    }

    @Test("Enter sets active state")
    func enterSetsActiveState() {
        let state = WallpaperPickerState()
        let testWallpaperID = WallpaperRegistry.shared.wallpapers.first?.id ?? "test"

        state.enter(currentWallpaperID: testWallpaperID)

        #expect(state.isActive == true)
        #expect(state.centeredWallpaperID == testWallpaperID)
    }

    @Test("Exit clears active state")
    func exitClearsActiveState() {
        let state = WallpaperPickerState()

        state.enter(currentWallpaperID: "test")
        #expect(state.isActive == true)

        state.exit()
        #expect(state.isActive == false)
    }

    @Test("Update centered wallpaper")
    func updateCenteredWallpaper() {
        let state = WallpaperPickerState()
        let wallpapers = WallpaperRegistry.shared.wallpapers

        guard wallpapers.count >= 2 else {
            return // Skip if not enough wallpapers
        }

        state.updateCenteredWallpaper(forIndex: 1)

        #expect(state.carouselIndex == 1)
        #expect(state.centeredWallpaperID == wallpapers[1].id)
    }

    @Test("Prewarmed wallpaper IDs")
    func prewarmedWallpaperIDs() {
        let state = WallpaperPickerState()
        let wallpapers = WallpaperRegistry.shared.wallpapers

        guard wallpapers.count >= 3 else {
            return // Skip if not enough wallpapers
        }

        // Set to middle of list
        state.updateCenteredWallpaper(forIndex: 1)

        let prewarmed = state.prewarmedWallpaperIDs

        // Should include center, left neighbor, and right neighbor
        #expect(prewarmed.contains(wallpapers[0].id))
        #expect(prewarmed.contains(wallpapers[1].id))
        #expect(prewarmed.contains(wallpapers[2].id))
    }

    @Test("Store and retrieve snapshot")
    func storeAndRetrieveSnapshot() {
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
        #expect(retrieved != nil)
        #expect(retrieved?.wallpaperID == "test-wallpaper")
        #expect(retrieved?.captureTime == 1.5)
    }

    @Test("Snapshot for nonexistent wallpaper returns nil")
    func snapshotForNonexistentWallpaperReturnsNil() {
        let state = WallpaperPickerState()

        let retrieved = state.snapshot(for: "nonexistent")
        #expect(retrieved == nil)
    }

    @Test("Confirm selection updates configuration")
    func confirmSelectionUpdatesConfiguration() {
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

        #expect(configuration.selectedWallpaperID == secondWallpaper.id)
    }
}

// MARK: - WallpaperRegistry Tests

@Suite("WallpaperRegistry Tests")
@MainActor
struct WallpaperRegistryTests {

    @Test("Registry contains wallpapers")
    func registryContainsWallpapers() {
        let wallpapers = WallpaperRegistry.shared.wallpapers

        #expect(wallpapers.isEmpty == false)
    }

    @Test("Wallpapers have unique IDs")
    func wallpapersHaveUniqueIDs() {
        let wallpapers = WallpaperRegistry.shared.wallpapers
        let ids = Set(wallpapers.map(\.id))

        #expect(ids.count == wallpapers.count)
    }

    @Test("Wallpapers have display names")
    func wallpapersHaveDisplayNames() {
        for wallpaper in WallpaperRegistry.shared.wallpapers {
            #expect(wallpaper.displayName.isEmpty == false)
        }
    }
}

// MARK: - WallpaperSnapshot Tests

@Suite("WallpaperSnapshot Tests")
struct WallpaperSnapshotTests {

    @Test("Snapshot stores data")
    func snapshotStoresData() {
        let image = UIImage()

        let snapshot = WallpaperSnapshot(
            wallpaperID: "my-wallpaper",
            image: image,
            captureTime: 2.5
        )

        #expect(snapshot.wallpaperID == "my-wallpaper")
        #expect(snapshot.captureTime == 2.5)
    }
}
