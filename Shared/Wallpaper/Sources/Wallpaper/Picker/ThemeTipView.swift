//
//  ThemeTipView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/30/25.
//

import SwiftUI

/// A tip view that informs users about the tap-and-hold gesture to reveal the theme picker.
///
/// Display logic is controlled by `ThemePickerPersistence.shouldShowTip`.
/// Use the debug panel to reset tip state for testing.
public struct ThemeTipView: View {
    public typealias Dismissal = () -> Void

    @Binding var isVisible: Bool
    private let onDismiss: Dismissal

    /// The Space Mountain theme used as the background.
    private var spaceMountainTheme: LoadedTheme? {
        ThemeRegistry.shared.theme(for: "neon_topology_iso")
    }

    public init(isVisible: Binding<Bool>, onDismiss: @escaping Dismissal = { }) {
        self._isVisible = isVisible
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mountain.2.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white.opacity(0.8))

            // Tip content
            VStack(alignment: .leading, spacing: 2) {
                Text("Pick a theme")
                    .font(.caption.weight(.heavy).smallCaps())
                    .foregroundStyle(.white.opacity(0.8))

                Text("Tap and hold anywhere")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }

            Spacer()

            // Close button
            Button {
                withAnimation(.easeOut(duration: 0.25)) {
                    isVisible = false
                }
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
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
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .scale(scale: 0.9).combined(with: .opacity)
        ))
    }
}
