//
//  MaterialView.swift
//  Wallpaper
//
//  Material blur effect view for overlays.
//
//  Created by Jake Bromberg on 01/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

#if os(iOS) || os(tvOS)
import UIKit

/// A custom material background view with configurable blur and tint overlay.
///
/// Provides fine-grained control over blur radius and overlay opacity,
/// replacing the discrete SwiftUI Material types.
public struct MaterialView: View {
    /// The blur radius applied to the background. Higher values create more blur.
    public var blurRadius: CGFloat

    /// The opacity of the tint overlay (0.0 to 1.0).
    public var overlayOpacity: CGFloat

    /// How "dark" the overlay is (0.0 = fully light/white, 1.0 = fully dark/black).
    /// Values between 0 and 1 will crossfade between white and black overlays.
    public var darkProgress: CGFloat

    /// The corner radius of the material shape.
    public var cornerRadius: CGFloat

    /// Convenience initializer using a boolean for dark/light.
    public init(
        blurRadius: CGFloat = 10,
        overlayOpacity: CGFloat = 0,
        isDark: Bool = true,
        cornerRadius: CGFloat = 12
    ) {
        self.blurRadius = blurRadius
        self.overlayOpacity = overlayOpacity
        self.darkProgress = isDark ? 1.0 : 0.0
        self.cornerRadius = cornerRadius
    }

    /// Initializer with explicit dark progress for smooth transitions.
    public init(
        blurRadius: CGFloat = 10,
        overlayOpacity: CGFloat = 0,
        darkProgress: CGFloat,
        cornerRadius: CGFloat = 12
    ) {
        self.blurRadius = blurRadius
        self.overlayOpacity = overlayOpacity
        self.darkProgress = darkProgress
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        // Use dark blur style - the overlay handles the visual tint
        VariableBlurView(blurRadius: blurRadius, isDark: true)
            .overlay(
                ZStack {
                    // White overlay (visible when darkProgress is low)
                    Rectangle()
                        .fill(Color.white)
                        .opacity(overlayOpacity * (1 - darkProgress))

                    // Black overlay (visible when darkProgress is high)
                    Rectangle()
                        .fill(Color.black)
                        .opacity(overlayOpacity * darkProgress)
                }
            )
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Variable Blur View

/// A UIViewRepresentable that provides a configurable blur effect.
///
/// Uses UIVisualEffectView with a paused animator to control blur intensity,
/// providing hardware-accelerated blur without the overhead of double-blurring.
private struct VariableBlurView: UIViewRepresentable {
    var blurRadius: CGFloat
    var isDark: Bool

    /// Maximum blur radius that maps to animator fraction 1.0.
    private static let maxBlurRadius: CGFloat = 30.0

    func makeUIView(context: Context) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: isDark ? .dark : .light)
        let visualEffectView = UIVisualEffectView(effect: nil)

        // Set up animator to control blur intensity
        let animator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
            visualEffectView.effect = blurEffect
        }
        animator.pausesOnCompletion = true
        animator.fractionComplete = fractionForRadius(blurRadius)

        context.coordinator.animator = animator
        context.coordinator.visualEffectView = visualEffectView

        return visualEffectView
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        let newFraction = fractionForRadius(blurRadius)

        // Update blur intensity
        if let animator = context.coordinator.animator {
            animator.fractionComplete = newFraction
        }

        // Update blur style if dark/light changed
        let targetStyle: UIBlurEffect.Style = isDark ? .dark : .light
        if context.coordinator.currentStyle != targetStyle {
            context.coordinator.currentStyle = targetStyle

            // Recreate animator with new style
            context.coordinator.animator?.stopAnimation(true)
            context.coordinator.animator?.finishAnimation(at: .current)

            let newEffect = UIBlurEffect(style: targetStyle)
            let newAnimator = UIViewPropertyAnimator(duration: 1, curve: .linear) {
                uiView.effect = newEffect
            }
            newAnimator.pausesOnCompletion = true
            newAnimator.fractionComplete = newFraction
            context.coordinator.animator = newAnimator
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func fractionForRadius(_ radius: CGFloat) -> CGFloat {
        min(max(radius / Self.maxBlurRadius, 0), 1)
    }

    final class Coordinator {
        var animator: UIViewPropertyAnimator?
        var visualEffectView: UIVisualEffectView?
        var currentStyle: UIBlurEffect.Style = .dark

        deinit {
            // Animators must be stopped and finished before deallocation
            animator?.stopAnimation(true)
            animator?.finishAnimation(at: .current)
        }
    }
}

#else

// MARK: - macOS Fallback

public struct MaterialView: View {
    public var blurRadius: CGFloat
    public var overlayOpacity: CGFloat
    public var darkProgress: CGFloat
    public var cornerRadius: CGFloat

    public init(
        blurRadius: CGFloat = 10,
        overlayOpacity: CGFloat = 0,
        isDark: Bool = true,
        cornerRadius: CGFloat = 12
    ) {
        self.blurRadius = blurRadius
        self.overlayOpacity = overlayOpacity
        self.darkProgress = isDark ? 1.0 : 0.0
        self.cornerRadius = cornerRadius
    }

    public init(
        blurRadius: CGFloat = 10,
        overlayOpacity: CGFloat = 0,
        darkProgress: CGFloat,
        cornerRadius: CGFloat = 12
    ) {
        self.blurRadius = blurRadius
        self.overlayOpacity = overlayOpacity
        self.darkProgress = darkProgress
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(
                ZStack {
                    Rectangle()
                        .fill(Color.white)
                        .opacity(overlayOpacity * (1 - darkProgress))
                    Rectangle()
                        .fill(Color.black)
                        .opacity(overlayOpacity * darkProgress)
                }
            )
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

#endif
