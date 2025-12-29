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

    /// Preloads snapshots in the background at low priority using parallel tasks.
    /// Call this at app launch to have snapshots ready before the user enters picker mode.
    /// - Parameters:
    ///   - size: The size to render snapshots at.
    ///   - scale: The display scale factor.
    public func preloadSnapshotsInBackground(size: CGSize, scale: CGFloat) {
        // Skip if already generating or if we have all snapshots
        guard !isGeneratingSnapshots else { return }

        let wallpaperCount = WallpaperRegistry.shared.wallpapers.count
        guard snapshots.count < wallpaperCount else { return }

        isGeneratingSnapshots = true

        // Run at low priority to avoid impacting UI
        Task.detached(priority: .utility) { [weak self] in
            guard let service = await WallpaperSnapshotService() else {
                await self?.setGeneratingSnapshots(false)
                return
            }

            let wallpapers = await WallpaperRegistry.shared.wallpapers

            // Generate all snapshots in parallel
            await withTaskGroup(of: WallpaperSnapshot?.self) { group in
                for wallpaper in wallpapers {
                    group.addTask {
                        await service.generateSnapshot(for: wallpaper, size: size, scale: scale)
                    }
                }

                // Store results as they complete
                for await snapshot in group {
                    if let snapshot {
                        await self?.storeSnapshot(snapshot)
                    }
                }
            }

            await self?.setGeneratingSnapshots(false)
        }
    }

    // MARK: - Private

    private func indexFor(wallpaperID: String) -> Int {
        WallpaperRegistry.shared.wallpapers.firstIndex { $0.id == wallpaperID } ?? 0
    }
}
