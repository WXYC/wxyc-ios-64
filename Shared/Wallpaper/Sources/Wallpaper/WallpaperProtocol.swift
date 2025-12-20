//
//  WallpaperProtocol.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/18/25.
//

import SwiftUI

/// Minimum interface required for a wallpaper to be handled by the registry.
///
/// Use the `@Wallpaper` macro to automatically register wallpaper types:
/// ```swift
/// @Wallpaper
/// public final class MyWallpaper {
///     public let displayName = "My Wallpaper"
///
///     public func configure() {
///         // Custom initialization logic (loading settings, etc.)
///     }
///
///     public func makeView() -> some View { ... }
///     public func makeDebugControls() -> EmptyView? { nil }
///     public func reset() { }
/// }
/// ```
public protocol WallpaperProtocol: Identifiable {
    associatedtype WallpaperView: View
    associatedtype DebugControls: View

    var id: String { get }
    var displayName: String { get }

    init()

    /// Called by the macro-generated `init()` for custom initialization logic.
    /// Implement this method to load settings from UserDefaults or perform other setup.
    func configure()

    func makeView() -> WallpaperView
    func makeDebugControls() -> DebugControls?
    func reset()
}

extension WallpaperProtocol {
    public var id: String { String(describing: type(of: self)) }
}
