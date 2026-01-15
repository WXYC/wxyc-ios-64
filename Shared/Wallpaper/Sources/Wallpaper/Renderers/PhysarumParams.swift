//
//  PhysarumParams.swift
//  Wallpaper
//
//  Parameters for physarum simulation, matching the Metal PhysarumParams struct.
//  Supports interpolation between presets for smooth transitions.
//
//  Created by Claude on 1/15/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Lerpable
import simd

/// Physarum simulation parameters matching the Metal shader struct.
/// All values are in simulation units (angles in radians, distances in pixels).
public struct PhysarumParams: Sendable, Lerpable {
    // Base values (when sensed trail = 0)
    public var sensorDistance0: Float
    public var sensorAngle0: Float
    public var rotationAngle0: Float
    public var moveDistance0: Float

    // Amplitude modulation based on sensed trail value
    public var sensorDistanceAmplitude: Float
    public var sensorAngleAmplitude: Float
    public var rotationAngleAmplitude: Float
    public var moveDistanceAmplitude: Float

    // Exponents for pow(sensedValue, exponent)
    public var sensorDistanceExponent: Float
    public var sensorAngleExponent: Float
    public var rotationAngleExponent: Float
    public var moveDistanceExponent: Float

    // Sensing offset bias
    public var sensorBias1: Float
    public var sensorBias2: Float

    // Other parameters
    public var depositAmount: Float
    public var decayFactor: Float
    public var sensingFactor: Float

    // Padding for 16-byte alignment
    private var _padding: Float = 0

    /// Default parameters for basic physarum behavior
    public static let `default` = PhysarumParams(
        sensorDistance0: 12.0,
        sensorAngle0: 0.35,
        rotationAngle0: 0.25,
        moveDistance0: 1.2,
        sensorDistanceAmplitude: 0.0,
        sensorAngleAmplitude: 0.0,
        rotationAngleAmplitude: 0.0,
        moveDistanceAmplitude: 0.0,
        sensorDistanceExponent: 2.0,
        sensorAngleExponent: 1.0,
        rotationAngleExponent: 1.0,
        moveDistanceExponent: 3.0,
        sensorBias1: 0.0,
        sensorBias2: 0.0,
        depositAmount: 1.0,
        decayFactor: 0.92,
        sensingFactor: 22.0
    )

    public init(
        sensorDistance0: Float,
        sensorAngle0: Float,
        rotationAngle0: Float,
        moveDistance0: Float,
        sensorDistanceAmplitude: Float,
        sensorAngleAmplitude: Float,
        rotationAngleAmplitude: Float,
        moveDistanceAmplitude: Float,
        sensorDistanceExponent: Float,
        sensorAngleExponent: Float,
        rotationAngleExponent: Float,
        moveDistanceExponent: Float,
        sensorBias1: Float,
        sensorBias2: Float,
        depositAmount: Float,
        decayFactor: Float,
        sensingFactor: Float
    ) {
        self.sensorDistance0 = sensorDistance0
        self.sensorAngle0 = sensorAngle0
        self.rotationAngle0 = rotationAngle0
        self.moveDistance0 = moveDistance0
        self.sensorDistanceAmplitude = sensorDistanceAmplitude
        self.sensorAngleAmplitude = sensorAngleAmplitude
        self.rotationAngleAmplitude = rotationAngleAmplitude
        self.moveDistanceAmplitude = moveDistanceAmplitude
        self.sensorDistanceExponent = sensorDistanceExponent
        self.sensorAngleExponent = sensorAngleExponent
        self.rotationAngleExponent = rotationAngleExponent
        self.moveDistanceExponent = moveDistanceExponent
        self.sensorBias1 = sensorBias1
        self.sensorBias2 = sensorBias2
        self.depositAmount = depositAmount
        self.decayFactor = decayFactor
        self.sensingFactor = sensingFactor
    }

    /// Linear interpolation between two parameter sets.
    /// Conforms to `Lerpable` protocol.
    public static func lerp(_ a: PhysarumParams, _ b: PhysarumParams, t: Double) -> PhysarumParams {
        PhysarumParams(
            sensorDistance0: .lerp(a.sensorDistance0, b.sensorDistance0, t: t),
            sensorAngle0: .lerp(a.sensorAngle0, b.sensorAngle0, t: t),
            rotationAngle0: .lerp(a.rotationAngle0, b.rotationAngle0, t: t),
            moveDistance0: .lerp(a.moveDistance0, b.moveDistance0, t: t),
            sensorDistanceAmplitude: .lerp(a.sensorDistanceAmplitude, b.sensorDistanceAmplitude, t: t),
            sensorAngleAmplitude: .lerp(a.sensorAngleAmplitude, b.sensorAngleAmplitude, t: t),
            rotationAngleAmplitude: .lerp(a.rotationAngleAmplitude, b.rotationAngleAmplitude, t: t),
            moveDistanceAmplitude: .lerp(a.moveDistanceAmplitude, b.moveDistanceAmplitude, t: t),
            sensorDistanceExponent: .lerp(a.sensorDistanceExponent, b.sensorDistanceExponent, t: t),
            sensorAngleExponent: .lerp(a.sensorAngleExponent, b.sensorAngleExponent, t: t),
            rotationAngleExponent: .lerp(a.rotationAngleExponent, b.rotationAngleExponent, t: t),
            moveDistanceExponent: .lerp(a.moveDistanceExponent, b.moveDistanceExponent, t: t),
            sensorBias1: .lerp(a.sensorBias1, b.sensorBias1, t: t),
            sensorBias2: .lerp(a.sensorBias2, b.sensorBias2, t: t),
            depositAmount: .lerp(a.depositAmount, b.depositAmount, t: t),
            decayFactor: .lerp(a.decayFactor, b.decayFactor, t: t),
            sensingFactor: .lerp(a.sensingFactor, b.sensingFactor, t: t)
        )
    }
}

// MARK: - Preset Definitions

extension PhysarumParams {
    /// "waves_upturn" - flowing wave patterns
    public static let wavesUpturn = PhysarumParams(
        sensorDistance0: 0.0,
        sensorAngle0: 0.18,
        rotationAngle0: 0.26,
        moveDistance0: 0.0,
        sensorDistanceAmplitude: 0.03,
        sensorAngleAmplitude: 0.0,
        rotationAngleAmplitude: 0.0,
        moveDistanceAmplitude: 0.65,
        sensorDistanceExponent: 0.82,
        sensorAngleExponent: 1.0,
        rotationAngleExponent: 1.0,
        moveDistanceExponent: 20.0,
        sensorBias1: 0.2,
        sensorBias2: 0.9,
        depositAmount: 1.0,
        decayFactor: 0.92,
        sensingFactor: 31.5
    )

    /// "vertebrata" - branching spine-like structures
    public static let vertebrata = PhysarumParams(
        sensorDistance0: 17.92,
        sensorAngle0: 0.52,
        rotationAngle0: 0.18,
        moveDistance0: 0.1,
        sensorDistanceAmplitude: 0.0,
        sensorAngleAmplitude: 0.0,
        rotationAngleAmplitude: 0.0,
        moveDistanceAmplitude: 0.17,
        sensorDistanceExponent: 2.0,
        sensorAngleExponent: 1.0,
        rotationAngleExponent: 1.0,
        moveDistanceExponent: 6.05,
        sensorBias1: 0.0,
        sensorBias2: 0.0,
        depositAmount: 1.0,
        decayFactor: 0.92,
        sensingFactor: 18.0
    )

    /// "star_network" - interconnected star patterns
    public static let starNetwork = PhysarumParams(
        sensorDistance0: 3.0,
        sensorAngle0: 1.03,
        rotationAngle0: 1.42,
        moveDistance0: 0.83,
        sensorDistanceAmplitude: 0.4,
        sensorAngleAmplitude: 2.0,
        rotationAngleAmplitude: 0.75,
        moveDistanceAmplitude: 0.11,
        sensorDistanceExponent: 10.17,
        sensorAngleExponent: 2.3,
        rotationAngleExponent: 20.0,
        moveDistanceExponent: 1.56,
        sensorBias1: 1.07,
        sensorBias2: 0.0,
        depositAmount: 1.0,
        decayFactor: 0.92,
        sensingFactor: 13.0
    )

    /// "enmeshed_singularities" - dense tangled patterns
    public static let enmeshedSingularities = PhysarumParams(
        sensorDistance0: 0.0,
        sensorAngle0: 0.61,
        rotationAngle0: 3.35,
        moveDistance0: 0.75,
        sensorDistanceAmplitude: 0.19,
        sensorAngleAmplitude: 0.0,
        rotationAngleAmplitude: 0.0,
        moveDistanceAmplitude: 0.06,
        sensorDistanceExponent: 8.51,
        sensorAngleExponent: 1.0,
        rotationAngleExponent: 1.0,
        moveDistanceExponent: 12.62,
        sensorBias1: 0.0,
        sensorBias2: 0.0,
        depositAmount: 1.0,
        decayFactor: 0.92,
        sensingFactor: 34.0
    )

    /// "strike" - bold linear patterns
    public static let strike = PhysarumParams(
        sensorDistance0: 0.0,
        sensorAngle0: 0.41,
        rotationAngle0: 0.1,
        moveDistance0: 0.3,
        sensorDistanceAmplitude: 402.0,
        sensorAngleAmplitude: 0.0,
        rotationAngleAmplitude: 0.0,
        moveDistanceAmplitude: 0.0,
        sensorDistanceExponent: 32.88,
        sensorAngleExponent: 3.0,
        rotationAngleExponent: 1.0,
        moveDistanceExponent: 6.0,
        sensorBias1: 0.0,
        sensorBias2: 0.0,
        depositAmount: 1.0,
        decayFactor: 0.92,
        sensingFactor: 32.0
    )

    /// All available presets for cycling
    /// Note: Start with vertebrata because it has non-zero moveDistance0 for proper bootstrapping.
    /// wavesUpturn has moveDistance0=0, requiring existing trails to move.
    public static let allPresets: [PhysarumParams] = [
        .vertebrata,
        .starNetwork,
        .enmeshedSingularities,
        .strike,
        .wavesUpturn
    ]

    /// Preset names for display
    public static let presetNames: [String] = [
        "Vertebrata",
        "Star Network",
        "Enmeshed",
        "Strike",
        "Waves"
    ]
}
