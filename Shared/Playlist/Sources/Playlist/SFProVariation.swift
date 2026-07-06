//
//  SFProVariation.swift
//  Playlist
//
//  A point in SF Pro's variable-font design space, used by the on-air banner controls.
//
//  Created by Jake Bromberg on 07/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - SFProFontAxis

/// A variable-font axis exposed by the SF Pro system font.
///
/// SF Pro ships four registered axes; their tags, ranges, and defaults below were read
/// from the live font via `CTFontCopyVariationAxes`. Only ``weight`` has a Swift
/// convenience API, so the banner drives all four through the raw variation dictionary.
public enum SFProFontAxis: String, CaseIterable, Identifiable, Sendable {
    case weight
    case width
    case opticalSize
    case grade

    public var id: String { rawValue }

    /// The OpenType 4-character axis tag (`wght`, `wdth`, `opsz`, `GRAD`).
    public var tag: String {
        switch self {
        case .weight: "wght"
        case .width: "wdth"
        case .opticalSize: "opsz"
        case .grade: "GRAD"
        }
    }

    /// A human-readable label for the debug controls.
    public var displayName: String {
        switch self {
        case .weight: "Weight"
        case .width: "Width"
        case .opticalSize: "Optical Size"
        case .grade: "Grade"
        }
    }

    /// The CoreText variation-axis identifier: the tag's ASCII bytes packed big-endian.
    public var identifier: UInt32 { Self.identifier(for: tag) }

    /// The axis's valid range, as reported by the SF Pro variation table.
    public var range: ClosedRange<Double> {
        switch self {
        case .weight: 1...1000
        case .width: 30...150
        case .opticalSize: 17...96
        case .grade: 400...1000
        }
    }

    /// The value used by ``SFProVariation`` when unspecified — the tuned DJ-handle look:
    /// a semibold-plus weight, fully expanded width, tight text optical size, and a heavy grade.
    public var defaultValue: Double {
        switch self {
        case .weight: 648
        case .width: 150
        case .opticalSize: 17
        case .grade: 936
        }
    }

    /// Packs a four-character axis tag into its CoreText `UInt32` identifier.
    public static func identifier(for tag: String) -> UInt32 {
        tag.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | ($1.value & 0xFF) }
    }
}

// MARK: - SFProVariation

/// A concrete set of values across SF Pro's four variable-font axes.
///
/// ``variationDictionary`` produces the `kCTFontVariationAttribute` payload the view layer
/// applies to a `CTFont`; values are clamped to each axis's range so a stale or extreme
/// persisted value can't produce a degenerate font.
public struct SFProVariation: Hashable, Sendable {
    public var weight: Double
    public var width: Double
    public var opticalSize: Double
    public var grade: Double

    public init(
        weight: Double = SFProFontAxis.weight.defaultValue,
        width: Double = SFProFontAxis.width.defaultValue,
        opticalSize: Double = SFProFontAxis.opticalSize.defaultValue,
        grade: Double = SFProFontAxis.grade.defaultValue
    ) {
        self.weight = weight
        self.width = width
        self.opticalSize = opticalSize
        self.grade = grade
    }

    /// The value for a given axis.
    public func value(for axis: SFProFontAxis) -> Double {
        switch axis {
        case .weight: weight
        case .width: width
        case .opticalSize: opticalSize
        case .grade: grade
        }
    }

    /// CoreText axis-identifier → value map for `kCTFontVariationAttribute`, each value
    /// clamped into its axis range.
    public var variationDictionary: [UInt32: Double] {
        var dictionary: [UInt32: Double] = [:]
        for axis in SFProFontAxis.allCases {
            let clamped = min(max(value(for: axis), axis.range.lowerBound), axis.range.upperBound)
            dictionary[axis.identifier] = clamped
        }
        return dictionary
    }
}
