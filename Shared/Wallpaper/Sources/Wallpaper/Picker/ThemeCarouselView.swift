//
//  ThemeCarouselView.swift
//  Wallpaper
//
//  Horizontal carousel for browsing themes.
//
//  Created by Jake Bromberg on 12/21/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Horizontal carousel view showing all available themes.
/// Only the centered theme renders live; others show static snapshots.
struct ThemeCarouselView: View {
    @Bindable var configuration: ThemeConfiguration
    @Bindable var pickerState: ThemePickerState
    let screenSize: CGSize

    /// The photo storage for the photo picker card.
    let photoStorage: PhotoBackgroundStorageProtocol

    /// Scale factor for theme cards relative to screen size.
    private let cardScale: CGFloat = 0.75

    /// Corner radius for theme cards.
    private let cardCornerRadius: CGFloat = 40

    /// Spacing between cards.
    private let cardSpacing: CGFloat = 16

    /// Registry themes only; the photo card is rendered separately.
    private var registryThemes: [LoadedTheme] {
        ThemeRegistry.shared.themes
    }

    private var cardSize: CGSize {
        CGSize(
            width: screenSize.width * cardScale,
            height: screenSize.height * cardScale
        )
    }

    /// Index of the photo card (after all registry themes).
    private var photoCardIndex: Int {
        registryThemes.count
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    // Theme cards from the registry
                    ForEach(Array(registryThemes.enumerated()), id: \.element.id) { index, theme in
                        ThemeCardView(
                            theme: theme,
                            configuration: configuration,
                            cardSize: cardSize,
                            cornerRadius: cardCornerRadius
                        )
                        .id(index)
                        .onTapGesture {
                            handleCardTap(at: index)
                        }
                    }

                    // Photo picker card at the end
                    PhotoPickerCard(
                        storage: photoStorage,
                        cardSize: cardSize,
                        cornerRadius: cardCornerRadius,
                        onCardTapped: {
                            handleCardTap(at: photoCardIndex)
                        },
                        onPhotoSaved: {
                            pickerState.refreshPhotoTheme(storage: photoStorage)
                        }
                    )
                    .id(photoCardIndex)
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
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.x
            } action: { _, newOffset in
                pickerState.updateTransitionProgress(
                    scrollOffset: newOffset,
                    cardWidth: cardSize.width,
                    cardSpacing: cardSpacing,
                    horizontalPadding: (screenSize.width - cardSize.width) / 2,
                    includesPhotoCard: true
                )
            }
            .onChange(of: pickerState.carouselIndex) { _, newIndex in
                pickerState.updateCenteredTheme(forIndex: newIndex)
            }
            .onAppear {
                // Ensure scroll position is set correctly on initial appearance
                proxy.scrollTo(pickerState.carouselIndex, anchor: .center)
            }
        }
        .accessibilityIdentifier("themeCarousel")
        .background(Color.black)
        .environment(\.wallpaperAnimationStartTime, configuration.animationStartTime)
    }

    private func handleCardTap(at index: Int) {
        if pickerState.carouselIndex == index {
            // Already centered - confirm selection
            if index == photoCardIndex {
                // Photo card: only confirm if a photo is available
                if pickerState.photoTheme != nil {
                    confirmSelectionAndExit()
                }
            } else {
                confirmSelectionAndExit()
            }
        } else {
            withAnimation(.spring(duration: 0.3)) {
                pickerState.carouselIndex = index
            }
        }
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
