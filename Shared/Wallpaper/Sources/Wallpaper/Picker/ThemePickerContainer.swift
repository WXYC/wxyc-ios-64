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

    /// Blur radius - interpolated during picker transitions, otherwise from configuration.
    /// Uses effective values which respect user overrides for the selected theme.
    private var effectiveBlurRadius: Double {
        if let transition = pickerState.themeTransition, pickerState.isActive {
            let fromRadius = configuration.effectiveBlurRadius(for: transition.fromTheme.id)
            let toRadius = configuration.effectiveBlurRadius(for: transition.toTheme.id)
            return fromRadius + (toRadius - fromRadius) * transition.progress
        } else {
            return configuration.effectiveBlurRadius
        }
    }

    /// Overlay opacity - interpolated during picker transitions, otherwise from configuration.
    /// Uses effective values which respect user overrides for the selected theme.
    private var effectiveOverlayOpacity: Double {
        if let transition = pickerState.themeTransition, pickerState.isActive {
            let fromOpacity = configuration.effectiveOverlayOpacity(for: transition.fromTheme.id)
            let toOpacity = configuration.effectiveOverlayOpacity(for: transition.toTheme.id)
            return fromOpacity + (toOpacity - fromOpacity) * transition.progress
        } else {
            return configuration.effectiveOverlayOpacity
        }
    }

    /// Whether the overlay is dark - interpolated during picker transitions, otherwise from configuration.
    /// Uses effective values which respect user overrides for the selected theme.
    private var effectiveOverlayIsDark: Bool {
        if let transition = pickerState.themeTransition, pickerState.isActive {
            // Use the target theme's isDark during transitions
            return configuration.effectiveOverlayIsDark(for: transition.toTheme.id)
        } else {
            return configuration.effectiveOverlayIsDark
        }
    }

    /// Interpolated accent color during picker transitions.
    /// Uses RGB interpolation to avoid rainbow effects when transitioning between distant hues.
    private var effectiveAccentColor: AccentColor {
        if let transition = pickerState.themeTransition, pickerState.isActive {
            let fromColor = configuration.effectiveAccentColor(for: transition.fromTheme.id)
            let toColor = configuration.effectiveAccentColor(for: transition.toTheme.id)
            return fromColor.interpolated(to: toColor, progress: transition.progress)
        } else {
            return configuration.effectiveAccentColor
        }
    }

    /// Accent hue (normalized 0.0-1.0) from interpolated accent color.
    private var effectiveAccentHue: Double {
        effectiveAccentColor.normalizedHue
    }

    /// Accent saturation from interpolated accent color.
    private var effectiveAccentSaturation: Double {
        effectiveAccentColor.saturation
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
                    .environment(\.currentBlurRadius, effectiveBlurRadius)
                    .environment(\.currentOverlayOpacity, effectiveOverlayOpacity)
                    .environment(\.currentOverlayIsDark, effectiveOverlayIsDark)
                    .environment(\.currentAccentHue, effectiveAccentHue)
                    .environment(\.currentAccentSaturation, effectiveAccentSaturation)
                    .environment(\.currentLCDMinBrightness, configuration.lcdMinBrightness)
                    .environment(\.currentLCDMaxBrightness, configuration.lcdMaxBrightness)
                    .environment(\.currentLCDBrightnessOffset, effectiveLCDBrightnessOffset)
                    .environment(\.wallpaperMeshGradientPalette, configuration.meshGradientPalette)
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
