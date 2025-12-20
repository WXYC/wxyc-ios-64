//
//  WallpaperMacros.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/19/25.
//

/// Macro that auto-registers a wallpaper type and generates init().
///
/// Usage:
/// ```swift
/// @Wallpaper
/// public final class MyWallpaper: WallpaperProtocol {
///     public let displayName = "My Wallpaper"
///
///     public func configure() {
///         // Custom initialization logic
///     }
///
///     public func makeView() -> some View { ... }
///     public func makeDebugControls() -> EmptyView? { nil }
///     public func reset() { }
/// }
/// ```
///
/// The macro generates:
/// - `_registered` static property that registers the type with WallpaperProvider
/// - `init()` that triggers registration and calls `configure()`
@attached(member, names: named(_registered), named(init))
public macro Wallpaper() = #externalMacro(
    module: "WallpaperMacroPlugin",
    type: "WallpaperMacro"
)
