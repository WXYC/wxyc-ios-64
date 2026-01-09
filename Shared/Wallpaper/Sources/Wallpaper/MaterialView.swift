//
//  MaterialView.swift
//  Wallpaper
//
//  Created by Jake Bromberg on 1/8/26.
//

import SwiftUI

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
