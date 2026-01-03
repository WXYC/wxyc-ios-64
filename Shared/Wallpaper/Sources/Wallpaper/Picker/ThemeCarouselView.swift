//
//  ThemeCarouselView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
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

    /// Scale factor for theme cards relative to screen size.
    private let cardScale: CGFloat = 0.75

    /// Corner radius for theme cards.
    private let cardCornerRadius: CGFloat = 40

    /// Spacing between cards.
    private let cardSpacing: CGFloat = 16

    private var themes: [LoadedTheme] {
        ThemeRegistry.shared.themes
    }

    private var cardSize: CGSize {
        CGSize(
            width: screenSize.width * cardScale,
            height: screenSize.height * cardScale
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: cardSpacing) {
                    ForEach(Array(themes.enumerated()), id: \.element.id) { index, theme in
                        ThemeCardView(
                            theme: theme,
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
