//
//  WallpaperPickerTests.swift
//  WXYCTests
//
//  Tests for wallpaper picker state management.
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
    }

    @Test("Enter sets active state")
    func enterSetsActiveState() {
        let state = WallpaperPickerState()
        let testWallpaperID = WallpaperRegistry.shared.wallpapers.first?.id ?? "test"

        state.enter(currentWallpaperID: testWallpaperID)

        #expect(state.isActive == true)
        #expect(state.centeredWallpaperID == testWallpaperID)
    }

    @Test("Enter sets correct carousel index for each wallpaper")
    func enterSetsCorrectCarouselIndex() {
        let state = WallpaperPickerState()
        let wallpapers = WallpaperRegistry.shared.wallpapers

        for (expectedIndex, wallpaper) in wallpapers.enumerated() {
            state.enter(currentWallpaperID: wallpaper.id)

            #expect(state.carouselIndex == expectedIndex, "Expected index \(expectedIndex) for wallpaper '\(wallpaper.id)', but got \(state.carouselIndex)")
            #expect(state.centeredWallpaperID == wallpaper.id)
        }
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
