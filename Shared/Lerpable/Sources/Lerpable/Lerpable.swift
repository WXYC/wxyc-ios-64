//
//  Lerpable.swift
//  Lerpable
//
//  Protocol and macro for linear interpolation of value types. Types conforming
//  to Lerpable can be smoothly interpolated between two values using a parameter t.
//
//  Created by Jake Bromberg on 01/15/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics

/// A type that can be linearly interpolated.
public protocol Lerpable {
    /// Linearly interpolates between two values.
    /// - Parameters:
    ///   - a: The start value (returned when t = 0)
    ///   - b: The end value (returned when t = 1)
    ///   - t: The interpolation factor, typically in [0, 1]
    /// - Returns: The interpolated value
    static func lerp(_ a: Self, _ b: Self, t: Double) -> Self
}

// MARK: - Standard Library Conformances

extension Double: Lerpable {
    public static func lerp(_ a: Double, _ b: Double, t: Double) -> Double {
        a + (b - a) * t
    }
}

extension Float: Lerpable {
    public static func lerp(_ a: Float, _ b: Float, t: Double) -> Float {
        a + (b - a) * Float(t)
    }
}

extension CGFloat: Lerpable {
    public static func lerp(_ a: CGFloat, _ b: CGFloat, t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
}

// MARK: - Integer Conformances (with rounding)

extension Int: Lerpable {
    public static func lerp(_ a: Int, _ b: Int, t: Double) -> Int {
        Int((Double(a) + (Double(b) - Double(a)) * t).rounded())
    }
}

extension Int32: Lerpable {
    public static func lerp(_ a: Int32, _ b: Int32, t: Double) -> Int32 {
        Int32((Double(a) + (Double(b) - Double(a)) * t).rounded())
    }
}

extension UInt32: Lerpable {
    public static func lerp(_ a: UInt32, _ b: UInt32, t: Double) -> UInt32 {
        UInt32((Double(a) + (Double(b) - Double(a)) * t).rounded())
    }
}

// MARK: - Macro Declaration

/// Automatically generates `Lerpable` conformance for a struct.
///
/// All stored properties must themselves conform to `Lerpable`.
///
/// ```swift
/// @Lerpable
/// struct Point {
///     var x: Double
///     var y: Double
/// }
///
/// let start = Point(x: 0, y: 0)
/// let end = Point(x: 10, y: 20)
/// let mid = Point.lerp(start, end, t: 0.5)  // Point(x: 5, y: 10)
/// ```
@attached(extension, conformances: Lerpable, names: named(lerp))
public macro Lerpable() = #externalMacro(module: "LerpableMacros", type: "LerpableMacro")
