//
//  ThemeCardView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/20/25.
//

import SwiftUI

/// A card view that displays a live theme preview.
struct ThemeCardView: View {
    let theme: LoadedTheme
    let cardSize: CGSize
    let cornerRadius: CGFloat

    var body: some View {
        VStack(spacing: 12) {
            // Theme name label above the card
            Text(theme.displayName)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

            // Wallpaper card - always live, using reduced quality for picker
            WallpaperRendererFactory.makeView(for: theme)
                .environment(\.wallpaperQualityProfile, .picker)
                .frame(width: cardSize.width, height: cardSize.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }
}
