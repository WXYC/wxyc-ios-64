//
//  LerpableTests.swift
//  LerpableTests
//
//  Tests for the Lerpable macro and protocol, verifying correct interpolation
//  behavior for primitive types and macro-generated conformances.
//
//  Created by Jake Bromberg on 01/15/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Lerpable

@Lerpable
struct Point {
    var x: Double
    var y: Double
}

@Lerpable
struct Color {
    var r: Float
    var g: Float
    var b: Float
    var a: Float
}

@Lerpable
struct Transform {
    var position: Point
    var scale: Double
}

@Suite("Lerpable")
struct LerpableTests {

    @Test("Lerp at t=0 returns start value")
    func lerpAtZero() {
        let start = Point(x: 0, y: 0)
        let end = Point(x: 10, y: 20)
        let result = Point.lerp(start, end, t: 0)

        #expect(result.x == 0)
        #expect(result.y == 0)
    }

    @Test("Lerp at t=1 returns end value")
    func lerpAtOne() {
        let start = Point(x: 0, y: 0)
        let end = Point(x: 10, y: 20)
        let result = Point.lerp(start, end, t: 1)

        #expect(result.x == 10)
        #expect(result.y == 20)
    }

    @Test("Lerp at t=0.5 returns midpoint")
    func lerpAtHalf() {
        let start = Point(x: 0, y: 0)
        let end = Point(x: 10, y: 20)
        let result = Point.lerp(start, end, t: 0.5)

        #expect(result.x == 5)
        #expect(result.y == 10)
    }

    @Test("Lerp works with Float properties")
    func lerpFloat() {
        let black = Color(r: 0, g: 0, b: 0, a: 1)
        let white = Color(r: 1, g: 1, b: 1, a: 1)
        let gray = Color.lerp(black, white, t: 0.5)

        #expect(gray.r == 0.5)
        #expect(gray.g == 0.5)
        #expect(gray.b == 0.5)
        #expect(gray.a == 1)
    }

    @Test("Lerp works with nested Lerpable types")
    func lerpNested() {
        let start = Transform(position: Point(x: 0, y: 0), scale: 1)
        let end = Transform(position: Point(x: 100, y: 200), scale: 2)
        let mid = Transform.lerp(start, end, t: 0.5)

        #expect(mid.position.x == 50)
        #expect(mid.position.y == 100)
        #expect(mid.scale == 1.5)
    }

    @Test("Lerp supports extrapolation (t > 1)")
    func lerpExtrapolate() {
        let start = Point(x: 0, y: 0)
        let end = Point(x: 10, y: 10)
        let result = Point.lerp(start, end, t: 2)

        #expect(result.x == 20)
        #expect(result.y == 20)
    }

    @Test("Lerp supports negative t values")
    func lerpNegativeT() {
        let start = Point(x: 10, y: 10)
        let end = Point(x: 20, y: 20)
        let result = Point.lerp(start, end, t: -1)

        #expect(result.x == 0)
        #expect(result.y == 0)
    }

    @Test("Double lerp is precise")
    func doublePrecision() {
        let result = Double.lerp(0, 1, t: 0.3)
        #expect(result == 0.3)
    }

    @Test("Int lerp rounds correctly")
    func intRounding() {
        #expect(Int.lerp(0, 10, t: 0.24) == 2)
        #expect(Int.lerp(0, 10, t: 0.25) == 3)
        #expect(Int.lerp(0, 10, t: 0.5) == 5)
    }
}
