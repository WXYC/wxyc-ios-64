//
//  ThemePickerContainer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import SwiftUI

/// Container view that manages the theme picker mode.
///
/// Responsibilities:
/// - Switches between single wallpaper view and theme carousel
/// - Scales and clips content when picker is active
/// - Passes theme appearance to child views via environment
///
/// All appearance interpolation is handled by `ThemeConfiguration.currentAppearance`.
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
                    .environment(\.themeAppearance, configuration.currentAppearance)
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
