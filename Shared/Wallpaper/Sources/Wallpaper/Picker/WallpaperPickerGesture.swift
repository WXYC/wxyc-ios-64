//
//  WallpaperPickerGesture.swift
//  Wallpaper
//
//  Long press gesture to enter wallpaper picker mode.
//

#if os(iOS)
import SwiftUI
import UIKit

// MARK: - Long Press Gesture Behavior
//
// This view modifier provides the long press gesture to enter wallpaper picker mode.
//
// Requirements:
// 1. Long pressing (0.5 seconds) triggers wallpaper picker while finger is still down
// 2. Vertical dragging cancels the gesture and allows ScrollView scrolling
// 3. Horizontal dragging cancels the gesture and allows TabView swiping
//
// Implementation:
// Uses an introspection technique to find the underlying UIScrollView and attach
// a UILongPressGestureRecognizer directly to it. This ensures proper gesture
// coordination because the recognizer is part of the same UIKit gesture system
// as the scroll view's pan gesture.

/// View modifier that adds long press gesture to enter wallpaper picker mode.
struct WallpaperPickerGestureModifier: ViewModifier {
    @Bindable var pickerState: WallpaperPickerState
    @Bindable var configuration: WallpaperConfiguration

    func body(content: Content) -> some View {
        content
            .background {
                ScrollViewIntrospector { scrollView in
                    addLongPressGesture(to: scrollView)
                }
            }
    }

    private func addLongPressGesture(to scrollView: UIScrollView) {
        // Check if we already added our gesture recognizer
        let existingRecognizer = scrollView.gestureRecognizers?.first {
            $0 is WallpaperPickerLongPressGesture
        }
        guard existingRecognizer == nil else { return }

        let recognizer = WallpaperPickerLongPressGesture { [pickerState, configuration] in
            // Haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            // Enter wallpaper picker mode
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) {
                pickerState.enter(
                    currentWallpaperID: configuration.selectedWallpaperID
                )
            }
        }
        scrollView.addGestureRecognizer(recognizer)
    }
}

// MARK: - Custom Long Press Gesture Recognizer

/// A long press gesture recognizer configured for wallpaper picker activation.
private class WallpaperPickerLongPressGesture: UILongPressGestureRecognizer, UIGestureRecognizerDelegate {
    private let onLongPress: () -> Void

    init(onLongPress: @escaping () -> Void) {
        self.onLongPress = onLongPress
        super.init(target: nil, action: nil)

        minimumPressDuration = 0.5
        allowableMovement = 10
        delegate = self

        // Don't interfere with scroll/swipe
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false

        addTarget(self, action: #selector(handleGesture(_:)))
    }

    @objc private func handleGesture(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == .began {
            onLongPress()
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - ScrollView Introspection

/// A helper view that finds the underlying UIScrollView and calls a callback.
private struct ScrollViewIntrospector: UIViewRepresentable {
    let callback: (UIScrollView) -> Void

    func makeUIView(context: Context) -> IntrospectionView {
        let view = IntrospectionView()
        view.callback = callback
        return view
    }

    func updateUIView(_ uiView: IntrospectionView, context: Context) {
        uiView.callback = callback
    }
}

private class IntrospectionView: UIView {
    var callback: ((UIScrollView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()

        // Defer to allow SwiftUI to finish layout
        DispatchQueue.main.async { [weak self] in
            self?.findScrollView()
        }
    }

    private func findScrollView() {
        // Walk up the view hierarchy to find a UIScrollView
        var current: UIView? = self
        while let view = current {
            if let scrollView = view as? UIScrollView {
                callback?(scrollView)
                return
            }
            current = view.superview
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a long press gesture that enters wallpaper picker mode.
    ///
    /// The gesture triggers after 0.5 seconds while the finger is still down.
    /// Moving more than 10 points cancels the gesture, allowing normal
    /// scrolling and horizontal swiping for tab navigation.
    ///
    /// - Parameters:
    ///   - pickerState: The wallpaper picker state to enter picker mode
    ///   - configuration: The wallpaper configuration to get the current wallpaper ID
    public func wallpaperPickerGesture(
        pickerState: WallpaperPickerState,
        configuration: WallpaperConfiguration
    ) -> some View {
        modifier(WallpaperPickerGestureModifier(
            pickerState: pickerState,
            configuration: configuration
        ))
    }
}
#endif
