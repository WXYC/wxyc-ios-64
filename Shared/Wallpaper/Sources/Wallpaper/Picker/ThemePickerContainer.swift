//
//  WallpaperPickerContainer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import SwiftUI

/// Container view that manages the wallpaper picker mode.
/// When inactive, displays a single wallpaper at full size.
/// When active, displays a carousel of live wallpapers with the content scaled down.
public struct WallpaperPickerContainer<Content: View>: View {
    @Bindable var configuration: WallpaperConfiguration
    @Bindable var pickerState: WallpaperPickerState
    @ViewBuilder var content: () -> Content

    /// Scale factor for content when picker is active.
    private let activeScale: CGFloat = 0.75

    /// Corner radius for content clipping when picker is active.
    private let activeCornerRadius: CGFloat = 60

    /// Animation for picker mode transitions.
    private let pickerAnimation: Animation = .spring(duration: 0.5, bounce: 0.2)

    public init(
        configuration: WallpaperConfiguration,
        pickerState: WallpaperPickerState,
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
                    WallpaperCarouselView(
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
                    .environment(\.isWallpaperPickerActive, pickerState.isActive)
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
