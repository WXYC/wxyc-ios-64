//
//  FastTrig.swift
//  WXUI
//
//  Fast trigonometry using lookup tables for animation performance.
//
//  Created by Jake Bromberg on 11/26/25.
//  Copyright © 2025 WXYC. All rights reserved.
//

import Foundation

// MARK: - Fast Trigonometry Lookup Table

/// Pre-computed sine values for the first quadrant (0 to π/2).
/// Uses 128 entries for smooth animation at 60 FPS without interpolation.
/// Other quadrants are derived using symmetry properties.
public enum FastTrig {
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
    public static func sin(_ radians: Float) -> Float {
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
    public static func cos(_ radians: Float) -> Float {
        sin(radians + .pi / 2)
    }
}
