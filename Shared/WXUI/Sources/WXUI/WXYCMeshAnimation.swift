//
//  BackgroundMesh.swift
//  WXUI
//
//  Created by Jake Bromberg on 11/25/25.
//

import SwiftUI

// MARK: - Fast Trigonometry Lookup Table

/// Pre-computed sine values for the first quadrant (0 to π/2).
/// Uses 128 entries for smooth animation at 60 FPS without interpolation.
/// Other quadrants are derived using symmetry properties.
private enum FastTrig {
    /// Number of entries in the lookup table (power of 2 for fast modulo).
    static let tableSize: Int = 128

    /// Pre-computed sine values for angles 0 to π/2.
    /// Entry i corresponds to angle (i / tableSize) * (π/2).
    static let sinLUT: [Float] = {
        var lut = [Float](repeating: 0, count: tableSize)
        let scale: Double = .pi / 2 / Double(tableSize)
        for i in 0..<tableSize {
            let angle: Double = Double(i) * scale
            lut[i] = Float(Darwin.sin(angle))
        }
        return lut
    }()

    /// Scale factor to convert radians to table index.
    /// For a full cycle (2π), we have 4 quadrants × tableSize entries.
    private static let radiansToIndex = Float(tableSize * 4) / (2 * .pi)

    /// Fast sine approximation using lookup table with quadrant symmetry.
    /// - Parameter radians: Angle in radians (should be pre-reduced to [0, 2π) for best precision).
    /// - Returns: Approximate sine value.
    static func sin(_ radians: Float) -> Float {
        // Convert to table index (assumes radians is already in reasonable range)
        let normalized = radians * radiansToIndex
        let fullIndex = Int(normalized) & (tableSize * 4 - 1)  // Modulo 512 via bitmask

        let quadrant = fullIndex / tableSize
        let indexInQuadrant = fullIndex & (tableSize - 1)  // Modulo 128 via bitmask

        switch quadrant {
        case 0: return sinLUT[indexInQuadrant]                           // Q1: direct
        case 1: return sinLUT[tableSize - 1 - indexInQuadrant]           // Q2: mirror
        case 2: return -sinLUT[indexInQuadrant]                          // Q3: negate
        default: return -sinLUT[tableSize - 1 - indexInQuadrant]         // Q4: mirror + negate
        }
    }

    /// Fast cosine approximation using lookup table.
    /// cos(θ) = sin(θ + π/2)
    static func cos(_ radians: Float) -> Float {
        sin(radians + .pi / 2)
    }
}

// MARK: - Mesh Animation View

public struct WXYCMeshAnimation: View {
    public init() {}

    public var body: some View {
        meshGradient
    }

    static let palette: [Color] = [
        .indigo,
        .orange,
        .pink,
        .purple,
        .yellow,
        .blue,
        .green,
    ]

    // Generate colors once at initialization
    static let gradientColors: [Color] = (0..<16).map { _ in
        palette.randomElement()!
    }

    public var meshGradient: TimelineView<AnimationTimelineSchedule, MeshGradient> {
        TimelineView(.animation) { context in
            // Reduce time to [0, 2π) in Double precision before converting to Float
            // This preserves animation detail for large timeIntervalSince1970 values
            let twoPi: Double = 2 * .pi
            let reducedTime = Float(context.date.timeIntervalSince1970.truncatingRemainder(dividingBy: twoPi))
            let offsetX = FastTrig.sin(reducedTime) * 0.25
            let offsetY = FastTrig.cos(reducedTime) * 0.25

            MeshGradient(
                width: 4,
                height: 4,
                points: [
                    [0.0, 0.0], [0.3, 0.0], [0.7, 0.0], [1.0, 0.0],
                    [0.0, 0.3], [0.2 + offsetX, 0.4 + offsetY], [0.7 + offsetX, 0.2 + offsetY], [1.0, 0.3],
                    [0.0, 0.7], [0.3 + offsetX, 0.8], [0.7 + offsetX, 0.6], [1.0, 0.7],
                    [0.0, 1.0], [0.3, 1.0], [0.7, 1.0], [1.0, 1.0]
                ],
                colors: Self.gradientColors
            )
        }
    }
}

extension WXYCMeshAnimation: ShapeStyle {

}
