//
//  ThemePickerContainer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import SwiftUI

/// Container view that manages the theme picker mode.
/// When inactive, displays a single wallpaper at full size.
/// When active, displays a carousel of live themes with the content scaled down.
public struct ThemePickerContainer<Content: View>: View {
    @Bindable var configuration: ThemeConfiguration
    @Bindable var pickerState: ThemePickerState
    @ViewBuilder var content: () -> Content

    /// Scale factor for content when picker is active.
    private let activeScale: CGFloat = 0.75

    /// Corner radius for content clipping when picker is active.
    private let activeCornerRadius: CGFloat = 60

    /// Animation for picker mode transitions.
    private let pickerAnimation: Animation = .spring(duration: 0.5, bounce: 0.2)

    /// Current theme looked up from registry.
    private var currentTheme: LoadedTheme? {
        ThemeRegistry.shared.theme(for: configuration.selectedThemeID)
    }

    /// Material from the currently selected theme.
    private var currentThemeMaterial: Material {
        currentTheme?.manifest.materialWeight.material ?? .thinMaterial
    }

    /// Material tint - interpolated during picker transitions, otherwise from configuration.
    /// Uses effective values which respect user overrides for the selected theme.
    private var effectiveMaterialTint: Double {
        if let transition = pickerState.themeTransition, pickerState.isActive {
            let fromTint = configuration.effectiveMaterialTint(for: transition.fromTheme.id)
            let toTint = configuration.effectiveMaterialTint(for: transition.toTheme.id)
            return fromTint + (toTint - fromTint) * transition.progress
        } else {
            return configuration.effectiveMaterialTint
        }
    }

    /// Accent hue - interpolated during picker transitions, otherwise from configuration.
    /// Uses effective values which respect user overrides for the selected theme.
    private var effectiveAccentHue: Double {
        if let transition = pickerState.themeTransition, pickerState.isActive {
            let fromHue = configuration.effectiveAccentColor(for: transition.fromTheme.id).normalizedHue
            let toHue = configuration.effectiveAccentColor(for: transition.toTheme.id).normalizedHue
            return fromHue + (toHue - fromHue) * transition.progress
        } else {
            return configuration.effectiveAccentColor.normalizedHue
        }
    }

    /// Accent saturation - interpolated during picker transitions, otherwise from configuration.
    /// Uses effective values which respect user overrides for the selected theme.
    private var effectiveAccentSaturation: Double {
        if let transition = pickerState.themeTransition, pickerState.isActive {
            let fromSat = configuration.effectiveAccentColor(for: transition.fromTheme.id).saturation
            let toSat = configuration.effectiveAccentColor(for: transition.toTheme.id).saturation
            return fromSat + (toSat - fromSat) * transition.progress
        } else {
            return configuration.effectiveAccentColor.saturation
        }
    }

    /// LCD brightness offset - interpolated during picker transitions, otherwise from configuration.
    /// Uses effective values which respect user overrides for the selected theme.
    private var effectiveLCDBrightnessOffset: Double {
        if let transition = pickerState.themeTransition, pickerState.isActive {
            let fromOffset = configuration.effectiveLCDBrightnessOffset(for: transition.fromTheme.id)
            let toOffset = configuration.effectiveLCDBrightnessOffset(for: transition.toTheme.id)
            return fromOffset + (toOffset - fromOffset) * transition.progress
        } else {
            return configuration.effectiveLCDBrightnessOffset
        }
    }

    public init(
        configuration: ThemeConfiguration,
        pickerState: ThemePickerState,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.configuration = configuration
        self.pickerState = pickerState
        self.content = content
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background layer - either single wallpaper or carousel
                if pickerState.isActive {
                    ThemeCarouselView(
                        configuration: configuration,
                        pickerState: pickerState,
                        screenSize: geometry.size
                    )
                    .transition(.opacity)
                } else {
                    WallpaperView(configuration: configuration)
                        .transition(.opacity)
                }

                // Content overlay - scales and clips when picker is active
                content()
                    .environment(\.isThemePickerActive, pickerState.isActive)
                    .environment(\.previewThemeTransition, pickerState.isActive ? pickerState.themeTransition : nil)
                    .environment(\.currentMaterial, currentThemeMaterial)
                    .environment(\.currentMaterialTint, effectiveMaterialTint)
                    .environment(\.currentAccentHue, effectiveAccentHue)
                    .environment(\.currentAccentSaturation, effectiveAccentSaturation)
                    .environment(\.currentLCDMinBrightness, configuration.lcdMinBrightness)
                    .environment(\.currentLCDMaxBrightness, configuration.lcdMaxBrightness)
                    .environment(\.currentLCDBrightnessOffset, effectiveLCDBrightnessOffset)
                    .clipShape(RoundedRectangle(cornerRadius: pickerState.isActive ? activeCornerRadius : 0))
                    .scaleEffect(pickerState.isActive ? activeScale : 1.0)
                    .offset(y: pickerState.isActive ? 16 : 0)
                    .allowsHitTesting(!pickerState.isActive)
                    .animation(pickerAnimation, value: pickerState.isActive)
            }
        }
        .ignoresSafeArea()
    }
}
