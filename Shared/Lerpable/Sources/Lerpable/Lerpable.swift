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
import simd

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

// MARK: - Default Implementations via Protocol Extensions

extension Lerpable where Self: BinaryFloatingPoint {
    public static func lerp(_ a: Self, _ b: Self, t: Double) -> Self {
        a + (b - a) * Self(t)
    }
}

extension Lerpable where Self: BinaryInteger {
    public static func lerp(_ a: Self, _ b: Self, t: Double) -> Self {
        Self((Double(a) + (Double(b) - Double(a)) * t).rounded())
    }
}

extension Lerpable where Self: SIMD, Self.Scalar: BinaryFloatingPoint {
    public static func lerp(_ a: Self, _ b: Self, t: Double) -> Self {
        a + (b - a) * Self.Scalar(t)
    }
}

// MARK: - Floating Point Conformances

extension Float: Lerpable {}
extension Double: Lerpable {}
extension CGFloat: Lerpable {}
#if arch(x86_64)
extension Float80: Lerpable {}
#endif

// MARK: - Integer Conformances

extension Int: Lerpable {}
extension Int8: Lerpable {}
extension Int16: Lerpable {}
extension Int32: Lerpable {}
extension Int64: Lerpable {}
extension UInt: Lerpable {}
extension UInt8: Lerpable {}
extension UInt16: Lerpable {}
extension UInt32: Lerpable {}
extension UInt64: Lerpable {}

// MARK: - SIMD Conformances

extension SIMD2: Lerpable where Scalar: BinaryFloatingPoint {}
extension SIMD3: Lerpable where Scalar: BinaryFloatingPoint {}
extension SIMD4: Lerpable where Scalar: BinaryFloatingPoint {}

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
