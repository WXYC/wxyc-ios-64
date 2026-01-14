//
//  ThemeCardView.swift
//  Wallpaper
//
//  Card view for theme selection carousel.
//
//  Created by Jake Bromberg on 12/21/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI

/// A card view that displays a live theme preview with material settings applied.
///
/// The wallpaper frame determines the card's size and centering. The label is
/// overlaid above the card so it doesn't affect vertical positioning when the
/// carousel centers on this view.
struct ThemeCardView: View {
    let theme: LoadedTheme
    let configuration: ThemeConfiguration
    let cardSize: CGSize
    let cornerRadius: CGFloat

    /// Space reserved above the card for the label.
    private let labelHeight: CGFloat = 40

    var body: some View {
        // Wallpaper card - determines the frame and centering
        WallpaperRendererFactory.makeView(for: theme)
            .environment(\.wallpaperQualityProfile, .picker)
            .frame(width: cardSize.width, height: cardSize.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.3), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .overlay(alignment: .top) {
                // Theme name label positioned above the card
                Text(theme.displayName)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    .offset(y: -labelHeight)
            }
    }
}
