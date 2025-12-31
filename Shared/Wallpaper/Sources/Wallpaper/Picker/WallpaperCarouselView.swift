//
//  WallpaperCarouselView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Horizontal carousel view showing all available wallpapers.
/// Only the centered wallpaper renders live; others show static snapshots.
struct WallpaperCarouselView: View {
    @Bindable var configuration: WallpaperConfiguration
    @Bindable var pickerState: WallpaperPickerState
    let screenSize: CGSize

    /// Scale factor for wallpaper cards relative to screen size.
    private let cardScale: CGFloat = 0.75

    /// Corner radius for wallpaper cards.
    private let cardCornerRadius: CGFloat = 40

    /// Spacing between cards.
    private let cardSpacing: CGFloat = 16

    private var wallpapers: [LoadedWallpaper] {
        WallpaperRegistry.shared.wallpapers
    }

    private var cardSize: CGSize {
        CGSize(
            width: screenSize.width * cardScale,
            height: screenSize.height * cardScale
        )
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: cardSpacing) {
                ForEach(Array(wallpapers.enumerated()), id: \.element.id) { index, wallpaper in
                    WallpaperCardView(
                        wallpaper: wallpaper,
                        cardSize: cardSize,
                        cornerRadius: cardCornerRadius
                    )
                    .id(index)
                    .onTapGesture {
                        if pickerState.carouselIndex == index {
                            confirmSelectionAndExit()
                        } else {
                            withAnimation(.spring(duration: 0.3)) {
                                pickerState.carouselIndex = index
                            }
                        }
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: Binding(
            get: { pickerState.carouselIndex },
            set: { newValue in
                if let newValue {
                    pickerState.carouselIndex = newValue
                }
            }
        ))
        .safeAreaPadding(.horizontal, (screenSize.width - cardSize.width) / 2)
        .onChange(of: pickerState.carouselIndex) { _, newIndex in
            pickerState.updateCenteredWallpaper(forIndex: newIndex)
        }
        .accessibilityIdentifier("wallpaperCarousel")
    }

    private func confirmSelectionAndExit() {
        // Haptic feedback
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif

        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            pickerState.confirmSelection(to: configuration)
            pickerState.exit()
        }
    }
}
