//
//  ThemePickerContainer.swift
//  Wallpaper
//
//  Container view managing theme picker presentation.
//
//  Created by Jake Bromberg on 12/21/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

/// Container view that manages the theme picker mode.
///
/// Responsibilities:
/// - Switches between single wallpaper view and theme carousel
/// - Scales and clips content when picker is active
/// - Passes theme appearance to child views via environment
/// - Interpolates appearance during picker transitions via `effectiveAppearance`
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

    /// Threshold for considering a theme "centered" in the picker.
    private let centeredThreshold: Double = 0.02

    /// The current theme appearance, interpolated during picker transitions.
    private var effectiveAppearance: ThemeAppearance {
        guard pickerState.isActive,
              let transition = pickerState.themeTransition else {
            return configuration.appearance(for: configuration.selectedThemeID)
        }

        // When centered on a theme, use its appearance directly (no interpolation)
        if transition.progress < centeredThreshold {
            return configuration.appearance(for: transition.fromTheme.id)
        }
        if transition.progress > (1 - centeredThreshold) {
            return configuration.appearance(for: transition.toTheme.id)
        }

        // Actively scrolling between themes - interpolate
        let fromAppearance = configuration.appearance(for: transition.fromTheme.id)
        let toAppearance = configuration.appearance(for: transition.toTheme.id)
        return ThemeAppearance.lerp(fromAppearance, toAppearance, t: transition.progress)
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
                    .offset(y: 16) // Align with content offset
                    .transition(.opacity)
                } else {
                    WallpaperView(configuration: configuration)
                        .transition(.opacity)
                }

                // Content overlay - scales and clips when picker is active
                content()
                    .environment(\.isThemePickerActive, pickerState.isActive)
                    .environment(\.themeAppearance, effectiveAppearance)
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
