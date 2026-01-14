//
//  AnimatedMeshGradient.swift
//  WXUI
//
//  Animated mesh gradient with configurable colors and time offset.
//
//  Created by Jake Bromberg on 01/09/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// An animated 4×4 mesh gradient that oscillates smoothly using fast trigonometry.
///
/// Use this as a background for placeholder artwork or decorative elements.
///
/// ```swift
/// AnimatedMeshGradient()  // Random colors, no offset
/// AnimatedMeshGradient(timeOffset: 5)  // Phase-shifted animation
/// AnimatedMeshGradient(colors: myColors)  // Custom colors
/// ```
public struct AnimatedMeshGradient: View {
    /// Colors for the 16 mesh control points.
    let colors: [Color]

    /// Time offset in seconds to phase-shift the animation.
    let timeOffset: TimeInterval

    /// Tracks whether the view is currently visible.
    @State private var isVisible = true

    /// Default color palette for random color generation.
    public static let defaultPalette: [Color] = [
        .indigo,
        .orange,
        .pink,
        .purple,
        .yellow,
        .blue,
        .green,
    ]

    /// Creates an animated mesh gradient.
    /// - Parameters:
    ///   - colors: Colors for the 16 mesh points. If nil, random colors are generated.
    ///   - timeOffset: Time offset in seconds to phase-shift the animation (default: 0).
    public init(
        colors: [Color]? = nil,
        timeOffset: TimeInterval = 0
    ) {
        self.colors = colors ?? Self.randomColors()
        self.timeOffset = timeOffset
    }

    /// Generates 16 random colors from the default palette.
    public static func randomColors(from palette: [Color] = defaultPalette) -> [Color] {
        (0..<16).map { _ in palette.randomElement()! }
    }

    public var body: some View {
        Group {
            if isVisible {
                TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
                    meshGradient(for: context.date)
                }
            } else {
                meshGradient(for: .now)
            }
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private func meshGradient(for date: Date) -> some View {
        // Reduce time to [0, 2π) in Double precision before converting to Float
        // This preserves animation detail for large timeIntervalSince1970 values
        let twoPi: Double = 2 * .pi
        let time = date.timeIntervalSince1970 + timeOffset
        let reducedTime = Float(time.truncatingRemainder(dividingBy: twoPi))
        let offsetX = FastTrig.sin(reducedTime) * 0.25
        let offsetY = FastTrig.cos(reducedTime) * 0.25

        return MeshGradient(
            width: 4,
            height: 4,
            points: [
                [0.0, 0.0], [0.3, 0.0], [0.7, 0.0], [1.0, 0.0],
                [0.0, 0.3], [0.2 + offsetX, 0.4 + offsetY], [0.7 + offsetX, 0.2 + offsetY], [1.0, 0.3],
                [0.0, 0.7], [0.3 + offsetX, 0.8], [0.7 + offsetX, 0.6], [1.0, 0.7],
                [0.0, 1.0], [0.3, 1.0], [0.7, 1.0], [1.0, 1.0]
            ],
            colors: colors
        )
    }
}

// MARK: - ShapeStyle Conformance

extension AnimatedMeshGradient: ShapeStyle {}
