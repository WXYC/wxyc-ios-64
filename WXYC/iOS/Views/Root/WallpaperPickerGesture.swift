//
//  WallpaperPickerGesture.swift
//  WXYC
//
//  Created by Jake Bromberg on 12/22/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import SwiftUI
import Wallpaper

// MARK: - Long Press Gesture Behavior
//
// This view modifier provides the long press gesture to enter wallpaper picker mode.
//
// Behavior:
// - After holding for 1 second without moving, the wallpaper picker opens
// - The action triggers while the finger is still down (not on release)
// - Moving the finger more than 10 points cancels the gesture
// - Horizontal swipes for TabView navigation work normally
// - Vertical scrolling in ScrollView works normally
//
// Implementation Notes:
// - Uses a short minimumDuration (0.01s) to detect touch start immediately
// - The `pressing` callback starts a 1-second Task timer
// - The gesture's built-in `maximumDistance` cancels if user drags
// - When the gesture ends (drag or lift), `pressing(false)` cancels the timer

/// View modifier that adds long press gesture to enter wallpaper picker mode.
struct WallpaperPickerGestureModifier: ViewModifier {
    @Environment(Singletonia.self) private var appState
    @State private var longPressTask: Task<Void, Never>?

    /// Duration in seconds before the wallpaper picker activates.
    private let pressDuration: TimeInterval = 1.0

    /// Maximum distance in points the finger can move before the gesture cancels.
    private let maximumDistance: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .onLongPressGesture(
                minimumDuration: 0.01,
                maximumDistance: maximumDistance,
                pressing: { isPressing in
                    if isPressing {
                        startLongPressTimer()
                    } else {
                        cancelLongPressTimer()
                    }
                },
                perform: {
                    // This fires on release after minimumDuration (0.01s).
                    // We handle the action in the timer instead, so nothing to do here.
                }
            )
    }

    /// Starts a timer that triggers wallpaper picker mode after the press duration.
    private func startLongPressTimer() {
        longPressTask = Task { @MainActor in
            do {
                // Wait for the press duration (minus the small minimumDuration)
                try await Task.sleep(for: .seconds(pressDuration))

                // If we get here, the task wasn't cancelled (finger didn't move/lift)
                enterWallpaperPicker()
            } catch {
                // Task was cancelled (finger moved or lifted) - do nothing
            }
        }
    }

    /// Cancels the pending long press timer.
    private func cancelLongPressTimer() {
        longPressTask?.cancel()
        longPressTask = nil
    }

    /// Enters wallpaper picker mode with haptic feedback.
    private func enterWallpaperPicker() {
        // Cancel the task reference since we're done
        longPressTask = nil

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Enter wallpaper picker mode
        withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
            appState.wallpaperPickerState.enter(
                currentWallpaperID: appState.wallpaperConfiguration.selectedWallpaperID
            )
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a long press gesture that enters wallpaper picker mode.
    ///
    /// The gesture triggers after 1 second while the finger is still down.
    /// Moving more than 10 points cancels the gesture, allowing normal
    /// scrolling and horizontal swiping for tab navigation.
    func wallpaperPickerGesture() -> some View {
        modifier(WallpaperPickerGestureModifier())
    }
}
