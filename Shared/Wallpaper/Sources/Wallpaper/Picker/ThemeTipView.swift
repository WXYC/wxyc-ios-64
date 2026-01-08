//
//  ThemeTipView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 12/30/25.
//

import SwiftUI

/// A tip view that informs users about the tap-and-hold gesture to reveal the theme picker.
///
/// Display Logic:
/// Shows on first launch, until dismissed; never shows again once dismissed.
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

// MARK: - Persistence & Analytics

extension ThemeTipView {
    private static let dismissedAtKey = "themeTip.dismissedAt"

    /// Number of days before re-showing the tip to users who dismissed without using the picker.
    private static let reShowCooldownDays: TimeInterval = 90

    /// Analytics handler for tip dismissal events.
    @MainActor
    private static var analytics: ThemePickerAnalytics?

    /// Sets the analytics handler for theme tip events.
    ///
    /// - Parameter analytics: The analytics implementation to use.
    @MainActor
    public static func setAnalytics(_ analytics: ThemePickerAnalytics) {
        self.analytics = analytics
    }

    /// Returns whether the theme tip should be shown.
    ///
    /// Shows the tip if:
    /// - User has never dismissed it, OR
    /// - User dismissed it but never used the picker AND 90+ days have passed
    public static func shouldShow() -> Bool {
        // If user has used the picker, never show the tip again
        if ThemePickerUsage.hasEverUsed {
            return false
        }

        // If never dismissed, show it
        guard let dismissedAt = UserDefaults.standard.object(forKey: dismissedAtKey) as? Date else {
            return true
        }

        // Re-show after cooldown period if user still hasn't used the picker
        let daysSinceDismissal = Date().timeIntervalSince(dismissedAt) / 86400
        return daysSinceDismissal >= reShowCooldownDays
    }

    /// Call this when the user dismisses the tip to prevent future displays.
    ///
    /// - Parameter userInitiated: Whether the user tapped the dismiss button (true)
    ///   or the tip was auto-dismissed because they entered the picker (false).
    @MainActor
    public static func recordDismissal(userInitiated: Bool = false) {
        // Only record analytics for user-initiated dismissals
        if userInitiated {
            analytics?.record(ThemeTipDismissedEvent(
                hadEverEnteredPicker: ThemePickerUsage.hasEverUsed
            ))
        }

        UserDefaults.standard.set(Date(), forKey: dismissedAtKey)
    }

    /// Resets the theme tip state (useful for testing).
    public static func resetState() {
        UserDefaults.standard.removeObject(forKey: dismissedAtKey)
    }
}
