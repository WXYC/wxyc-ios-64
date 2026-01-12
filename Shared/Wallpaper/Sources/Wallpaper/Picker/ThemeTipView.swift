//
//  ThemeTipView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/30/25.
//

import SwiftUI
import WXUI

/// A tip view that informs users about the tap-and-hold gesture to reveal the theme picker.
///
/// Display logic is controlled by `ThemePickerPersistence.shouldShowTip`.
/// Use the debug panel to reset tip state for testing.
public struct ThemeTipView: View {
    @Binding var isVisible: Bool
    private let onDismiss: () -> Void

    /// The Space Mountain theme used as the background.
    private var spaceMountainTheme: LoadedTheme? {
        ThemeRegistry.shared.theme(for: "neon_topology_iso")
    }

    public init(isVisible: Binding<Bool>, onDismiss: @escaping () -> Void = { }) {
        self._isVisible = isVisible
        self.onDismiss = onDismiss
    }

    public var body: some View {
        TipView(
            iconName: "mountain.2.circle.fill",
            caption: "Pick a theme",
            headline: "Tap and hold anywhere",
            isVisible: $isVisible,
            onDismiss: onDismiss
        ) {
            GeometryReader { geometry in
                if let theme = spaceMountainTheme {
                    // Render wallpaper at a larger fixed size so the shader looks correct,
                    // centered within the tip view's bounds
                    WallpaperRendererFactory.makeView(for: theme)
                        .frame(width: 1000, height: 600)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
