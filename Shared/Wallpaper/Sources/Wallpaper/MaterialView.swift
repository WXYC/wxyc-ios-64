//
//  MaterialView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 1/8/26.
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

    /// Whether the overlay is dark (black) or light (white).
    public var isDark: Bool

    /// The corner radius of the material shape.
    public var cornerRadius: CGFloat

    public init(
        blurRadius: CGFloat = 10,
        overlayOpacity: CGFloat = 0,
        isDark: Bool = true,
        cornerRadius: CGFloat = 12
    ) {
        self.blurRadius = blurRadius
        self.overlayOpacity = overlayOpacity
        self.isDark = isDark
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Rectangle()
            .fill(.clear)
            .background(
                // Base blur - extend beyond bounds so blur is consistent at edges
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .padding(-blurRadius) // extend beyond visible bounds
                    .blur(radius: blurRadius)
            )
            .overlay(
                // Light / dark tint
                Rectangle()
                    .fill(isDark ? Color.black : Color.white)
                    .opacity(overlayOpacity)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .compositingGroup()
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
    }
}

#else

// MARK: - macOS Fallback

public struct MaterialView: View {
    public var blurRadius: CGFloat
    public var overlayOpacity: CGFloat
    public var isDark: Bool
    public var cornerRadius: CGFloat

    public init(
        blurRadius: CGFloat = 10,
        overlayOpacity: CGFloat = 0,
        isDark: Bool = true,
        cornerRadius: CGFloat = 12
    ) {
        self.blurRadius = blurRadius
        self.overlayOpacity = overlayOpacity
        self.isDark = isDark
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(
                Rectangle()
                    .fill(isDark ? Color.black : Color.white)
                    .opacity(overlayOpacity)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
    }
}

#endif
