//
//  ThemeConfiguration.swift
//  Wallpaper
//
//  Complete theme configuration combining manifest and overrides.
//
//  Created by Jake Bromberg on 12/18/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Caching
import ColorPalette
import Core
import Foundation
import Observation
import SwiftUI

/// Main theme configuration - holds the selected theme ID.
@Observable
@MainActor
public final class ThemeConfiguration {

    // MARK: - LCD HSB Offset Defaults

    /// Default HSB offset for LCD min (top) segments.
    public static let defaultLCDMinOffset: HSBOffset = .defaultMin

    /// Default HSB offset for LCD max (bottom) segments.
    public static let defaultLCDMaxOffset: HSBOffset = .defaultMax

    // MARK: - Storage Keys

    private let storageKey = "wallpaper.selectedType.v3"
    private let defaultThemeID = "wxyc_gradient"

    // MARK: - Per-Theme Storage Keys

    private func accentHueOverrideKey(for themeID: String) -> String {
        "wallpaper.accentHueOverride.\(themeID)"
    }

    private func accentSaturationOverrideKey(for themeID: String) -> String {
        "wallpaper.accentSaturationOverride.\(themeID)"
    }

    private func overlayOpacityOverrideKey(for themeID: String) -> String {
        "wallpaper.overlayOpacityOverride.\(themeID)"
    }

    private func accentBrightnessOverrideKey(for themeID: String) -> String {
        "wallpaper.accentBrightnessOverride.\(themeID)"
    }

    private func blurRadiusOverrideKey(for themeID: String) -> String {
        "wallpaper.blurRadiusOverride.\(themeID)"
    }

    private func overlayDarknessOverrideKey(for themeID: String) -> String {
        "wallpaper.overlayDarknessOverride.\(themeID)"
    }

    private func lcdMinOffsetKey(for themeID: String) -> String {
        "wallpaper.lcdMinOffset.\(themeID)"
    }

    private func lcdMaxOffsetKey(for themeID: String) -> String {
        "wallpaper.lcdMaxOffset.\(themeID)"
    }

    private func meshGradientPaletteKey(for themeID: String) -> String {
        "wallpaper.meshGradientPalette.\(themeID)"
    }

    private func playbackBlendModeKey(for themeID: String) -> String {
        "wallpaper.playbackBlendMode.\(themeID)"
    }

    private func playbackDarknessKey(for themeID: String) -> String {
        "wallpaper.playbackDarkness.\(themeID)"
    }

    private func playbackAlphaKey(for themeID: String) -> String {
        "wallpaper.playbackAlpha.\(themeID)"
    }

    private func materialBlendModeKey(for themeID: String) -> String {
        "wallpaper.materialBlendMode.\(themeID)"
    }

    // MARK: - Dependencies

    private let registry: any ThemeRegistryProtocol
    private let defaults: DefaultsStorage

    /// Shared animation start time for all wallpaper renderers.
    /// This ensures picker previews and main view show synchronized animations.
    public private(set) var animationStartTime: Date = Date()

    public var selectedThemeID: String {
        didSet {
            defaults.set(selectedThemeID, forKey: storageKey)
            // Load overrides for the newly selected theme
            loadOverrides(for: selectedThemeID)
        }
    }

    /// Returns the currently selected theme, if it exists.
    public var selectedTheme: LoadedTheme? {
        registry.theme(for: selectedThemeID)
    }

    // MARK: - Accent Color Override

    /// Optional hue override (0-360). When nil, uses the theme's default hue.
    /// Stored per-theme so each theme remembers its customizations.
    public var accentHueOverride: Double? {
        didSet {
            let key = accentHueOverrideKey(for: selectedThemeID)
            if let hue = accentHueOverride {
                defaults.set(hue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Optional saturation override (0.0-1.0). When nil, uses the theme's default saturation.
    /// Stored per-theme so each theme remembers its customizations.
    public var accentSaturationOverride: Double? {
        didSet {
            let key = accentSaturationOverrideKey(for: selectedThemeID)
            if let saturation = accentSaturationOverride {
                defaults.set(saturation, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Overlay Opacity Override

    /// Optional overlay opacity override (0.0 to 1.0). When nil, uses the theme's default opacity.
    /// Stored per-theme so each theme remembers its customizations.
    public var overlayOpacityOverride: Double? {
        didSet {
            let key = overlayOpacityOverrideKey(for: selectedThemeID)
            if let opacity = overlayOpacityOverride {
                defaults.set(opacity, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Blur Radius Override

    /// Optional blur radius override (0.0 to 30.0). When nil, uses the theme's default blur radius.
    /// Stored per-theme so each theme remembers its customizations.
    public var blurRadiusOverride: Double? {
        didSet {
            let key = blurRadiusOverrideKey(for: selectedThemeID)
            if let radius = blurRadiusOverride {
                defaults.set(radius, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Returns the effective blur radius, applying any override to the current theme's blur radius.
    public var effectiveBlurRadius: Double {
        if let override = blurRadiusOverride {
            return override
        }
        guard let theme = registry.theme(for: selectedThemeID) else {
            return 8.0
        }
        return theme.manifest.blurRadius
    }

    // MARK: - Overlay Darkness Override

    /// Optional darkness override (0.0 = white, 1.0 = black). When nil, uses the theme's default.
    /// Stored per-theme so each theme remembers its customizations.
    public var overlayDarknessOverride: Double? {
        didSet {
            let key = overlayDarknessOverrideKey(for: selectedThemeID)
            if let darkness = overlayDarknessOverride {
                defaults.set(darkness, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Returns the overlay darkness (0.0 = white, 1.0 = black), applying any override to the current theme's setting.
    public var effectiveOverlayDarkness: Double {
        if let override = overlayDarknessOverride {
            return override
        }
        guard let theme = registry.theme(for: selectedThemeID) else {
            return 1.0
        }
        return theme.manifest.overlayDarkness
    }

    /// Returns the effective overlay opacity, applying any override to the current theme's opacity.
    public var effectiveOverlayOpacity: Double {
        if let override = overlayOpacityOverride {
            return override
        }
        guard let theme = registry.theme(for: selectedThemeID) else {
            return 0.0
        }
        return theme.manifest.overlayOpacity
    }

    // MARK: - LCD HSB Offset Settings

    /// HSB offset for LCD min (top) segments.
    /// Stored per-theme so each theme remembers its customizations.
    public var lcdMinOffset: HSBOffset = ThemeConfiguration.defaultLCDMinOffset {
        didSet {
            let key = lcdMinOffsetKey(for: selectedThemeID)
            if let data = try? JSONEncoder().encode(lcdMinOffset) {
                defaults.set(data, forKey: key)
            }
        }
    }

    /// HSB offset for LCD max (bottom) segments.
    /// Stored per-theme so each theme remembers its customizations.
    public var lcdMaxOffset: HSBOffset = ThemeConfiguration.defaultLCDMaxOffset {
        didSet {
            let key = lcdMaxOffsetKey(for: selectedThemeID)
            if let data = try? JSONEncoder().encode(lcdMaxOffset) {
                defaults.set(data, forKey: key)
            }
        }
    }

    // MARK: - Playback Blend Mode

    /// The blend mode for playback controls.
    /// Stored per-theme so each theme can have its own blend mode.
    public var playbackBlendMode: PlaybackBlendMode = .default {
        didSet {
            let key = playbackBlendModeKey(for: selectedThemeID)
            defaults.set(playbackBlendMode.rawValue, forKey: key)
        }
    }

    /// Returns the effective blend mode as a SwiftUI BlendMode.
    public var effectivePlaybackBlendMode: BlendMode {
        playbackBlendMode.blendMode
    }

    // MARK: - Playback Darkness

    /// The darkness level for playback controls (0.0 = original, 1.0 = fully dark).
    /// Stored per-theme so each theme can have its own darkness level.
    public var playbackDarkness: Double = 0.0 {
        didSet {
            let key = playbackDarknessKey(for: selectedThemeID)
            defaults.set(playbackDarkness, forKey: key)
        }
    }

    // MARK: - Playback Alpha

    /// The alpha/opacity for playback controls (0.0 = transparent, 1.0 = opaque).
    /// Stored per-theme so each theme can have its own alpha level.
    public var playbackAlpha: Double = 1.0 {
        didSet {
            let key = playbackAlphaKey(for: selectedThemeID)
            defaults.set(playbackAlpha, forKey: key)
        }
    }

    // MARK: - Material Blend Mode

    /// The blend mode for material overlays.
    /// Stored per-theme so each theme can have its own blend mode.
    public var materialBlendMode: MaterialBlendMode = .default {
        didSet {
            let key = materialBlendModeKey(for: selectedThemeID)
            defaults.set(materialBlendMode.rawValue, forKey: key)
        }
    }

    /// Returns the effective blend mode as a SwiftUI BlendMode.
    public var effectiveMaterialBlendMode: BlendMode {
        materialBlendMode.blendMode
    }

    /// Optional accent brightness override (0.5 to 1.5). When nil, uses the theme's default.
    /// Stored per-theme so each theme remembers its customizations.
    public var accentBrightnessOverride: Double? {
        didSet {
            let key = accentBrightnessOverrideKey(for: selectedThemeID)
            if let brightness = accentBrightnessOverride {
                defaults.set(brightness, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Mesh Gradient Palette

    /// The interpolated mesh gradient palette (16 SwiftUI Colors) for the current theme.
    /// Derived from cached HSB colors via MeshGradientPaletteInterpolator.
    public private(set) var meshGradientPalette: [Color]?

    /// Cached dominant HSB colors (3-5) extracted from wallpaper snapshot.
    /// Persisted per-theme to UserDefaults as JSON.
    private var cachedPaletteHSBColors: [HSBColor]? {
        didSet {
            // Persist to UserDefaults
            let key = meshGradientPaletteKey(for: selectedThemeID)
            if let colors = cachedPaletteHSBColors {
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(colors) {
                    defaults.set(data, forKey: key)
                }
            } else {
                defaults.removeObject(forKey: key)
            }

            // Recompute interpolated palette
            if let colors = cachedPaletteHSBColors, !colors.isEmpty {
                let interpolator = MeshGradientPaletteInterpolator()
                meshGradientPalette = interpolator.interpolate(colors)
            } else {
                meshGradientPalette = nil
            }
        }
    }

    /// Extracts and caches the mesh gradient palette from a wallpaper snapshot.
    /// - Parameter snapshot: UIImage snapshot of the current wallpaper.
    public func extractAndCachePalette(from snapshot: Core.Image) {
        let extractor = DominantColorExtractor()
        let colors = extractor.extractDominantColors(from: snapshot, count: 5)
        cachedPaletteHSBColors = colors.isEmpty ? nil : colors
    }

    /// Clears the cached palette for the current theme.
    public func clearCachedPalette() {
        cachedPaletteHSBColors = nil
    }

    /// Returns the effective accent color, applying any overrides to the current theme's accent.
    public var effectiveAccentColor: AccentColor {
        guard let theme = registry.theme(for: selectedThemeID) else {
            return AccentColor(
                hue: accentHueOverride ?? 0,
                saturation: accentSaturationOverride ?? 1.0,
                brightness: accentBrightnessOverride ?? 1.0
            )
        }
        let baseAccent = theme.manifest.accent
        return AccentColor(
            hue: accentHueOverride ?? baseAccent.hue,
            saturation: accentSaturationOverride ?? baseAccent.saturation,
            brightness: accentBrightnessOverride ?? baseAccent.brightness
        )
    }

    // MARK: - Effective Values for Any Theme

    /// Returns the effective accent color for a given theme ID.
    /// For the selected theme, uses in-memory overrides. For other themes, looks up stored overrides.
    public func effectiveAccentColor(for themeID: String) -> AccentColor {
        if themeID == selectedThemeID {
            return effectiveAccentColor
        }
        guard let theme = registry.theme(for: themeID) else {
            return AccentColor(hue: 0, saturation: 1.0, brightness: 1.0)
        }
        let baseAccent = theme.manifest.accent

        // Look up stored overrides for this theme
        let hueKey = accentHueOverrideKey(for: themeID)
        let satKey = accentSaturationOverrideKey(for: themeID)
        let brightnessKey = accentBrightnessOverrideKey(for: themeID)
        let storedHue = defaults.object(forKey: hueKey) != nil ? defaults.double(forKey: hueKey) : nil
        let storedSat = defaults.object(forKey: satKey) != nil ? defaults.double(forKey: satKey) : nil
        let storedBrightness = defaults.object(forKey: brightnessKey) != nil ? defaults.double(forKey: brightnessKey) : nil

        return AccentColor(
            hue: storedHue ?? baseAccent.hue,
            saturation: storedSat ?? baseAccent.saturation,
            brightness: storedBrightness ?? baseAccent.brightness
        )
    }

    /// Returns the effective overlay opacity for a given theme ID.
    /// For the selected theme, uses in-memory override. For other themes, looks up stored override.
    public func effectiveOverlayOpacity(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return effectiveOverlayOpacity
        }
        guard let theme = registry.theme(for: themeID) else {
            return 0.0
        }

        // Look up stored override for this theme
        let opacityKey = overlayOpacityOverrideKey(for: themeID)
        if defaults.object(forKey: opacityKey) != nil {
            return defaults.double(forKey: opacityKey)
        }
        return theme.manifest.overlayOpacity
    }


    /// Returns the effective blur radius for a given theme ID.
    /// For the selected theme, uses in-memory override. For other themes, looks up stored override.
    public func effectiveBlurRadius(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return effectiveBlurRadius
        }
        guard let theme = registry.theme(for: themeID) else {
            return 8.0
        }

        // Look up stored override for this theme
        let blurKey = blurRadiusOverrideKey(for: themeID)
        if defaults.object(forKey: blurKey) != nil {
            return defaults.double(forKey: blurKey)
        }
        return theme.manifest.blurRadius
    }

    /// Returns the overlay darkness for a given theme ID.
    /// For the selected theme, uses in-memory override. For other themes, looks up stored override.
    public func effectiveOverlayDarkness(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return effectiveOverlayDarkness
        }
        guard let theme = registry.theme(for: themeID) else {
            return 1.0
        }

        // Look up stored override for this theme
        let darknessKey = overlayDarknessOverrideKey(for: themeID)
        if defaults.object(forKey: darknessKey) != nil {
            return defaults.double(forKey: darknessKey)
        }
        return theme.manifest.overlayDarkness
    }

    /// Returns the LCD min offset for a given theme ID.
    public func lcdMinOffset(for themeID: String) -> HSBOffset {
        if themeID == selectedThemeID { return lcdMinOffset }
        return loadHSBOffset(forKey: lcdMinOffsetKey(for: themeID)) ?? Self.defaultLCDMinOffset
    }

    /// Returns the LCD max offset for a given theme ID.
    public func lcdMaxOffset(for themeID: String) -> HSBOffset {
        if themeID == selectedThemeID { return lcdMaxOffset }
        return loadHSBOffset(forKey: lcdMaxOffsetKey(for: themeID)) ?? Self.defaultLCDMaxOffset
    }

    /// Returns the effective playback blend mode for a given theme ID.
    /// For the selected theme, uses in-memory value. For other themes, looks up stored override.
    public func effectivePlaybackBlendMode(for themeID: String) -> BlendMode {
        if themeID == selectedThemeID {
            return effectivePlaybackBlendMode
        }

        // Look up stored override for this theme
        let key = playbackBlendModeKey(for: themeID)
        if let savedMode = defaults.string(forKey: key),
           let mode = PlaybackBlendMode(rawValue: savedMode) {
            return mode.blendMode
        }
        return PlaybackBlendMode.default.blendMode
    }

    /// Returns the playback darkness for a given theme ID.
    /// For the selected theme, uses in-memory value. For other themes, looks up stored value.
    public func playbackDarkness(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return playbackDarkness
        }

        let key = playbackDarknessKey(for: themeID)
        if defaults.object(forKey: key) != nil {
            return defaults.double(forKey: key)
        }
        return 0.0
    }

    /// Returns the playback alpha for a given theme ID.
    /// For the selected theme, uses in-memory value. For other themes, looks up stored value.
    public func playbackAlpha(for themeID: String) -> Double {
        if themeID == selectedThemeID {
            return playbackAlpha
        }

        let key = playbackAlphaKey(for: themeID)
        if defaults.object(forKey: key) != nil {
            return defaults.double(forKey: key)
        }
        return 1.0
    }

    /// Returns the effective material blend mode for a given theme ID.
    /// For the selected theme, uses in-memory value. For other themes, looks up stored override.
    public func effectiveMaterialBlendMode(for themeID: String) -> BlendMode {
        if themeID == selectedThemeID {
            return effectiveMaterialBlendMode
        }

        // Look up stored override for this theme
        let key = materialBlendModeKey(for: themeID)
        if let savedMode = defaults.string(forKey: key),
           let mode = MaterialBlendMode(rawValue: savedMode) {
            return mode.blendMode
        }
        return MaterialBlendMode.default.blendMode
    }

    // MARK: - Theme Appearance

    /// Returns the appearance for a specific theme, with any user overrides applied.
    public func appearance(for themeID: String) -> ThemeAppearance {
        ThemeAppearance(
            blurRadius: effectiveBlurRadius(for: themeID),
            overlayOpacity: effectiveOverlayOpacity(for: themeID),
            darkProgress: effectiveOverlayDarkness(for: themeID),
            accentColor: effectiveAccentColor(for: themeID),
            lcdMinOffset: lcdMinOffset(for: themeID),
            lcdMaxOffset: lcdMaxOffset(for: themeID),
            playbackBlendMode: DiscreteTransition(effectivePlaybackBlendMode(for: themeID)),
            playbackDarkness: playbackDarkness(for: themeID),
            playbackAlpha: playbackAlpha(for: themeID),
            materialBlendMode: DiscreteTransition(effectiveMaterialBlendMode(for: themeID))
        )
    }

    private func loadHSBOffset(forKey key: String) -> HSBOffset? {
        guard let data = defaults.data(forKey: key),
              let offset = try? JSONDecoder().decode(HSBOffset.self, from: data) else {
            return nil
        }
        return offset
    }

    // MARK: - Bulk Override Access

    /// Returns all overrides for a given theme as a ThemeOverrides struct.
    /// Used for export and bulk operations.
    public func overrides(for themeID: String) -> ThemeOverrides {
        if themeID == selectedThemeID {
            // Use in-memory values for selected theme
            return ThemeOverrides(
                accentHue: accentHueOverride,
                accentSaturation: accentSaturationOverride,
                accentBrightness: accentBrightnessOverride,
                overlayOpacity: overlayOpacityOverride,
                blurRadius: blurRadiusOverride,
                overlayDarkness: overlayDarknessOverride,
                lcdMinOffset: lcdMinOffset != Self.defaultLCDMinOffset ? lcdMinOffset : nil,
                lcdMaxOffset: lcdMaxOffset != Self.defaultLCDMaxOffset ? lcdMaxOffset : nil
            )
        }

        // Load from UserDefaults for non-selected themes
        return ThemeOverrides(
            accentHue: loadOptionalDouble(accentHueOverrideKey(for: themeID)),
            accentSaturation: loadOptionalDouble(accentSaturationOverrideKey(for: themeID)),
            accentBrightness: loadOptionalDouble(accentBrightnessOverrideKey(for: themeID)),
            overlayOpacity: loadOptionalDouble(overlayOpacityOverrideKey(for: themeID)),
            blurRadius: loadOptionalDouble(blurRadiusOverrideKey(for: themeID)),
            overlayDarkness: loadOptionalDouble(overlayDarknessOverrideKey(for: themeID)),
            lcdMinOffset: loadHSBOffset(forKey: lcdMinOffsetKey(for: themeID)),
            lcdMaxOffset: loadHSBOffset(forKey: lcdMaxOffsetKey(for: themeID))
        )
    }

    private func loadOptionalDouble(_ key: String) -> Double? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.double(forKey: key)
    }

    private func loadOptionalBool(_ key: String) -> Bool? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.bool(forKey: key)
    }

    // MARK: - Per-Theme Override Loading

    /// Loads overrides for a specific theme from UserDefaults.
    private func loadOverrides(for themeID: String) {
        let hueKey = accentHueOverrideKey(for: themeID)
        accentHueOverride = defaults.object(forKey: hueKey) != nil
            ? defaults.double(forKey: hueKey)
            : nil

        let satKey = accentSaturationOverrideKey(for: themeID)
        accentSaturationOverride = defaults.object(forKey: satKey) != nil
            ? defaults.double(forKey: satKey)
            : nil

        let brightnessKey = accentBrightnessOverrideKey(for: themeID)
        accentBrightnessOverride = defaults.object(forKey: brightnessKey) != nil
            ? defaults.double(forKey: brightnessKey)
            : nil

        let opacityKey = overlayOpacityOverrideKey(for: themeID)
        overlayOpacityOverride = defaults.object(forKey: opacityKey) != nil
            ? defaults.double(forKey: opacityKey)
            : nil

        let blurKey = blurRadiusOverrideKey(for: themeID)
        blurRadiusOverride = defaults.object(forKey: blurKey) != nil
            ? defaults.double(forKey: blurKey)
            : nil

        let overlayDarknessKey = overlayDarknessOverrideKey(for: themeID)
        overlayDarknessOverride = defaults.object(forKey: overlayDarknessKey) != nil
            ? defaults.double(forKey: overlayDarknessKey)
            : nil

        // Load LCD HSB offsets
        lcdMinOffset = loadHSBOffset(forKey: lcdMinOffsetKey(for: themeID)) ?? Self.defaultLCDMinOffset
        lcdMaxOffset = loadHSBOffset(forKey: lcdMaxOffsetKey(for: themeID)) ?? Self.defaultLCDMaxOffset

        // Load playback blend mode
        let blendModeKey = playbackBlendModeKey(for: themeID)
        if let savedMode = defaults.string(forKey: blendModeKey),
           let mode = PlaybackBlendMode(rawValue: savedMode) {
            playbackBlendMode = mode
        } else {
            playbackBlendMode = .default
        }

        // Load playback darkness
        let playbackDarknessKeyValue = playbackDarknessKey(for: themeID)
        playbackDarkness = defaults.object(forKey: playbackDarknessKeyValue) != nil
            ? defaults.double(forKey: playbackDarknessKeyValue)
            : 0.0

        // Load playback alpha
        let alphaKey = playbackAlphaKey(for: themeID)
        playbackAlpha = defaults.object(forKey: alphaKey) != nil
            ? defaults.double(forKey: alphaKey)
            : 1.0

        // Load material blend mode
        let materialBlendModeKeyValue = materialBlendModeKey(for: themeID)
        if let savedMode = defaults.string(forKey: materialBlendModeKeyValue),
           let mode = MaterialBlendMode(rawValue: savedMode) {
            materialBlendMode = mode
        } else {
            materialBlendMode = .default
        }

        // Load cached mesh gradient palette
        let paletteKey = meshGradientPaletteKey(for: themeID)
        if let data = defaults.data(forKey: paletteKey) {
            let decoder = JSONDecoder()
            if let colors = try? decoder.decode([HSBColor].self, from: data), !colors.isEmpty {
                let interpolator = MeshGradientPaletteInterpolator()
                meshGradientPalette = interpolator.interpolate(colors)
            } else {
                meshGradientPalette = nil
            }
        } else {
            meshGradientPalette = nil
        }
    }

    // MARK: - Initialization

    /// Creates a configuration with injected dependencies.
    /// - Parameters:
    ///   - registry: The theme registry for looking up themes.
    ///   - defaults: The UserDefaults instance for persistence.
    public init(
        registry: any ThemeRegistryProtocol = ThemeRegistry.shared,
        defaults: DefaultsStorage = UserDefaults.standard
    ) {
        self.registry = registry
        self.defaults = defaults

        let storedID = defaults.string(forKey: storageKey)
        // Map legacy IDs to new IDs
        self.selectedThemeID = Self.mapLegacyID(storedID, using: registry) ?? defaultThemeID

        // Load per-theme overrides for the selected theme (includes brightness settings)
        loadOverrides(for: selectedThemeID)
    }

    public func reset() {
        selectedThemeID = defaultThemeID
        accentHueOverride = nil
        accentSaturationOverride = nil
        accentBrightnessOverride = nil
        overlayOpacityOverride = nil
        blurRadiusOverride = nil
        overlayDarknessOverride = nil
        lcdMinOffset = Self.defaultLCDMinOffset
        lcdMaxOffset = Self.defaultLCDMaxOffset
        playbackBlendMode = .default
        playbackDarkness = 0.0
        playbackAlpha = 1.0
        materialBlendMode = .default
        meshGradientPalette = nil
        registry.themes.forEach { $0.parameterStore.reset() }
    }

    /// Clears any corrupted UserDefaults data for theme settings.
    public static func nukeLegacyData(defaults: DefaultsStorage = UserDefaults.standard) {
        defaults.removeObject(forKey: "wallpaper.selectedType.v3")
        defaults.removeObject(forKey: "wallpaper.selectedType")
    }

    /// Maps legacy wallpaper type IDs to new manifest-based IDs.
    private static func mapLegacyID(
        _ legacyID: String?,
        using registry: any ThemeRegistryProtocol
    ) -> String? {
        guard let legacyID else { return nil }

        // If it's already a new-style ID, return it
        if registry.theme(for: legacyID) != nil {
            return legacyID
        }

        // Map legacy class names to new manifest IDs
        let mapping: [String: String] = [
            "WXYCGradientWithNoiseWallpaper": "wxyc_gradient_noise",
            "WXYCGradientWallpaperImplementation": "wxyc_gradient",
            "WaterTurbulenceWallpaper": "water_turbulence",
            "WaterCausticsWallpaper": "water_caustics",
            "SpiralWallpaper": "spiral",
            "PerspexWebLatticeWallpaper": "perspex_web_lattice"
        ]

        return mapping[legacyID]
    }
}
