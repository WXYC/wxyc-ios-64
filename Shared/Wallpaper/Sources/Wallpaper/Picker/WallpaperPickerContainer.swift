//
//  WallpaperPickerContainer.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Container view that manages the wallpaper picker mode.
/// When inactive, displays a single wallpaper at full size.
/// When active, displays a carousel of wallpapers with the content scaled down.
public struct WallpaperPickerContainer<Content: View>: View {
    @Bindable var configuration: WallpaperConfiguration
    @Bindable var pickerState: WallpaperPickerState
    @ViewBuilder var content: () -> Content

    /// Scale factor for content when picker is active.
    private let activeScale: CGFloat = 0.75

    /// Corner radius for content clipping when picker is active.
    private let activeCornerRadius: CGFloat = 40

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
            let safeAreaTop = geometry.safeAreaInsets.top
            let safeAreaBottom = geometry.safeAreaInsets.bottom
            // When scaled, offset to center the content area (excluding safe areas) rather than the full frame
            let verticalOffset = pickerState.isActive ? (safeAreaTop - safeAreaBottom) * 0.5 * (1 - activeScale) : 0

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
                    .clipShape(RoundedRectangle(cornerRadius: pickerState.isActive ? activeCornerRadius : 0))
                    .scaleEffect(pickerState.isActive ? activeScale : 1.0)
                    .offset(y: verticalOffset)
                    .allowsHitTesting(!pickerState.isActive)
                    .animation(pickerAnimation, value: pickerState.isActive)
            }
            .onChange(of: pickerState.isActive) { wasActive, isNowActive in
                if isNowActive && !wasActive {
                    // Start generating snapshots when entering picker mode
                    // Use half resolution to reduce memory and speed up generation
                    let snapshotSize = CGSize(
                        width: geometry.size.width * 0.5,
                        height: geometry.size.height * 0.5
                    )
                    #if os(iOS)
                    let scale = UIScreen.main.scale
                    #else
                    let scale: CGFloat = 2.0
                    #endif
                    pickerState.startGeneratingSnapshots(size: snapshotSize, scale: scale)
                }
            }
        }
        .ignoresSafeArea()
    }
}
