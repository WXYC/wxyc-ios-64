//
//  DiscreteTransition.swift
//  Wallpaper
//
//  A generic type for transitioning between discrete values that cannot be
//  mathematically interpolated (e.g., enums, blend modes).
//
//  Created by Jake Bromberg on 01/12/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Lerpable
import SwiftUI

/// Represents a transition between two discrete values.
///
/// Use this type when you need to animate between values that cannot be
/// mathematically interpolated. The type provides both endpoints and a
/// progress value, allowing views to implement visual transitions like
/// crossfades.
///
/// Example usage:
/// ```swift
/// let transition = DiscreteTransition(from: .normal, to: .multiply, progress: 0.5)
///
/// ZStack {
///     content.blendMode(transition.from).opacity(transition.fromOpacity)
///     content.blendMode(transition.to).opacity(transition.toOpacity)
/// }
/// ```
public struct DiscreteTransition<Value: Equatable>: Equatable {
    /// The starting value of the transition.
    public let from: Value

    /// The ending value of the transition.
    public let to: Value

    /// The transition progress (0.0 = fully from, 1.0 = fully to).
    public let progress: CGFloat

    /// Creates a transition between two discrete values.
    ///
    /// - Parameters:
    ///   - from: The starting value.
    ///   - to: The ending value.
    ///   - progress: The transition progress (0.0 to 1.0).
    public init(from: Value, to: Value, progress: CGFloat) {
        self.from = from
        self.to = to
        self.progress = progress
    }

    /// Creates a static (non-transitioning) value.
    ///
    /// - Parameter value: The static value.
    public init(_ value: Value) {
        self.from = value
        self.to = value
        self.progress = 0
    }

    /// The opacity to apply to the "from" value for crossfade effects.
    public var fromOpacity: Double {
        1.0 - progress
    }

    /// The opacity to apply to the "to" value for crossfade effects.
    public var toOpacity: Double {
        Double(progress)
    }

    /// Returns the discrete value, snapping at the midpoint.
    ///
    /// Use this when crossfade isn't possible or desired.
    public var snapped: Value {
        progress > 0.5 ? to : from
    }

    /// Returns true if the transition is between different values.
    public var isTransitioning: Bool {
        from != to && progress > 0 && progress < 1
    }
}

// MARK: - Sendable Conformance

extension DiscreteTransition: Sendable where Value: Sendable {}

// MARK: - Lerpable Conformance

extension DiscreteTransition: Lerpable {
    public static func lerp(_ a: Self, _ b: Self, t: Double) -> Self {
        DiscreteTransition(from: a.snapped, to: b.snapped, progress: CGFloat(t))
    }
}

// MARK: - View Extension for Crossfade

public extension View {
    /// Applies a crossfade transition between two blend modes.
    ///
    /// Renders the view twice with different blend modes and crossfades
    /// between them based on the transition progress.
    ///
    /// - Parameter transition: The blend mode transition.
    /// - Returns: A view with crossfading blend modes applied.
    @ViewBuilder
    func blendMode(_ transition: DiscreteTransition<BlendMode>) -> some View {
        if transition.isTransitioning {
            ZStack {
                self.blendMode(transition.from).opacity(transition.fromOpacity)
                self.blendMode(transition.to).opacity(transition.toOpacity)
            }
        } else {
            self.blendMode(transition.snapped)
        }
    }
}
