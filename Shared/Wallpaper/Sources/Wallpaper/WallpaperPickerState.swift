//
//  WallpaperPickerState.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import Foundation
import Observation
import SwiftUI

// MARK: - Environment Key

/// Environment key to indicate whether the wallpaper picker is active.
/// Content can use this to adjust layout (e.g., disable safe area padding when scaled).
private struct WallpaperPickerActiveKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

public extension EnvironmentValues {
    var isWallpaperPickerActive: Bool {
        get { self[WallpaperPickerActiveKey.self] }
        set { self[WallpaperPickerActiveKey.self] = newValue }
    }
}

#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#endif

/// Represents a captured snapshot of a wallpaper at a specific animation time.
public struct WallpaperSnapshot: Sendable {
    public let wallpaperID: String
    public let image: PlatformImage
    /// The animation time offset when this snapshot was captured.
    /// Used to resume animation seamlessly when transitioning from snapshot to live.
    public let captureTime: Float

    public init(wallpaperID: String, image: PlatformImage, captureTime: Float) {
        self.wallpaperID = wallpaperID
        self.image = image
        self.captureTime = captureTime
    }
}

/// Observable state for the wallpaper picker mode.
/// Manages the picker lifecycle, carousel position, and snapshot caching.
@MainActor
@Observable
public final class WallpaperPickerState {
    /// Whether the picker mode is currently active.
    public var isActive: Bool = false

    /// The wallpaper ID currently centered in the carousel.
    /// This may differ from the selected wallpaper until the user confirms.
    public var centeredWallpaperID: String = ""

    /// The carousel page index (corresponds to wallpaper position in registry).
    public var carouselIndex: Int = 0

    /// Cached snapshots keyed by wallpaper ID.
    public private(set) var snapshots: [String: WallpaperSnapshot] = [:]

    /// Whether snapshots are currently being generated.
    public private(set) var isGeneratingSnapshots: Bool = false

    public init() {}

    // MARK: - Lifecycle

    /// Enters picker mode, centering on the currently selected wallpaper.
    /// - Parameter currentWallpaperID: The currently selected wallpaper ID to center on.
    public func enter(currentWallpaperID: String) {
        centeredWallpaperID = currentWallpaperID
        carouselIndex = indexFor(wallpaperID: currentWallpaperID)
        isActive = true
    }

    /// Confirms the current centered wallpaper as the selection.
    /// - Parameter configuration: The wallpaper configuration to update.
    public func confirmSelection(to configuration: WallpaperConfiguration) {
        configuration.selectedWallpaperID = centeredWallpaperID
    }

    /// Exits picker mode and cleans up resources.
    public func exit() {
        isActive = false

        // Delay snapshot cleanup to allow exit animation to complete
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                snapshots.removeAll()
            }
        }
    }

    // MARK: - Carousel Navigation

    /// Updates the centered wallpaper based on carousel index.
    /// - Parameter index: The new carousel index.
    public func updateCenteredWallpaper(forIndex index: Int) {
        let wallpapers = WallpaperRegistry.shared.wallpapers
        guard index >= 0 && index < wallpapers.count else { return }
        carouselIndex = index
        centeredWallpaperID = wallpapers[index].id
    }

    /// Returns the wallpaper IDs that should have pre-warmed renderers.
    /// This includes the center and immediate neighbors.
    public var prewarmedWallpaperIDs: Set<String> {
        let wallpapers = WallpaperRegistry.shared.wallpapers
        guard !wallpapers.isEmpty else { return [] }

        var ids: Set<String> = [centeredWallpaperID]

        // Add left neighbor
        if carouselIndex > 0 {
            ids.insert(wallpapers[carouselIndex - 1].id)
        }

        // Add right neighbor
        if carouselIndex < wallpapers.count - 1 {
            ids.insert(wallpapers[carouselIndex + 1].id)
        }

        return ids
    }

    // MARK: - Snapshots

    /// Stores a snapshot for a wallpaper.
    /// - Parameter snapshot: The snapshot to store.
    public func storeSnapshot(_ snapshot: WallpaperSnapshot) {
        snapshots[snapshot.wallpaperID] = snapshot
    }

    /// Returns the snapshot for a wallpaper, if available.
    /// - Parameter wallpaperID: The wallpaper ID to look up.
    /// - Returns: The snapshot if available, nil otherwise.
    public func snapshot(for wallpaperID: String) -> WallpaperSnapshot? {
        snapshots[wallpaperID]
    }

    /// Sets the snapshot generation state.
    /// - Parameter generating: Whether snapshots are being generated.
    public func setGeneratingSnapshots(_ generating: Bool) {
        isGeneratingSnapshots = generating
    }

    /// Starts generating snapshots for all wallpapers.
    /// Snapshots are generated asynchronously and stored as they complete.
    /// - Parameters:
    ///   - size: The size to render snapshots at.
    ///   - scale: The display scale factor.
    public func startGeneratingSnapshots(size: CGSize, scale: CGFloat) {
        guard !isGeneratingSnapshots else { return }

        Task { @MainActor in
            isGeneratingSnapshots = true
            defer { isGeneratingSnapshots = false }

            guard let service = WallpaperSnapshotService() else { return }

            // Generate snapshots prioritizing wallpapers near the current selection
            let wallpapers = WallpaperRegistry.shared.wallpapers
            let prioritizedWallpapers = prioritizeWallpapers(wallpapers, aroundIndex: carouselIndex)

            for wallpaper in prioritizedWallpapers {
                // Stop if picker is no longer active
                guard isActive else { break }

                // Skip if we already have a snapshot for this wallpaper
                if snapshots[wallpaper.id] != nil { continue }

                if let snapshot = await service.generateSnapshot(
                    for: wallpaper,
                    size: size,
                    scale: scale
                ) {
                    storeSnapshot(snapshot)
                }
            }
        }
    }

    /// Prioritizes wallpapers for snapshot generation.
    /// Order: current, neighbors, then outward from center.
    private func prioritizeWallpapers(_ wallpapers: [LoadedWallpaper], aroundIndex centerIndex: Int) -> [LoadedWallpaper] {
        guard !wallpapers.isEmpty else { return [] }

        var result: [LoadedWallpaper] = []
        var visited = Set<Int>()

        // Start with center
        if centerIndex >= 0 && centerIndex < wallpapers.count {
            result.append(wallpapers[centerIndex])
            visited.insert(centerIndex)
        }

        // Expand outward from center
        for offset in 1..<wallpapers.count {
            let leftIndex = centerIndex - offset
            let rightIndex = centerIndex + offset

            if leftIndex >= 0 && !visited.contains(leftIndex) {
                result.append(wallpapers[leftIndex])
                visited.insert(leftIndex)
            }

            if rightIndex < wallpapers.count && !visited.contains(rightIndex) {
                result.append(wallpapers[rightIndex])
                visited.insert(rightIndex)
            }
        }

        return result
    }

    // MARK: - Private

    private func indexFor(wallpaperID: String) -> Int {
        WallpaperRegistry.shared.wallpapers.firstIndex { $0.id == wallpaperID } ?? 0
    }
}
