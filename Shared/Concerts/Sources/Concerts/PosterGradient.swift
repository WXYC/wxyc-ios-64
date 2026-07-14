//
//  PosterGradient.swift
//  Concerts
//
//  Deterministic fallback artwork for the poster detail. Most concerts carry no
//  `image_url` today, so the poster detail paints a generated gradient instead.
//  The gradient must be stable — the same concert always paints the same colors,
//  on every run and every device — so the seed is a canonical 64-bit FNV-1a fold
//  over the venue slug + concert id, NOT Swift's `hashValue` (which is seeded per
//  run and would repaint a show differently each launch).
//
//  Colors are plain RGB data (no SwiftUI) so this stays unit-testable in the
//  package; the view maps a ``PosterRGB`` to a `Color`.
//
//  Created by Jake Bromberg on 07/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// An sRGB color as component doubles in `0...1`. Plain data so the gradient
/// palette can live in this Foundation-only package; the view builds a `Color`.
public struct PosterRGB: Sendable, Equatable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Builds a color from a `0xRRGGBB` literal — the form the prototype's
    /// palette was authored in.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// The two stops of a poster fallback gradient (top-leading → bottom-trailing).
public struct PosterGradientPair: Sendable, Equatable {
    public let start: PosterRGB
    public let end: PosterRGB

    public init(start: PosterRGB, end: PosterRGB) {
        self.start = start
        self.end = end
    }

    /// Convenience for the hex-authored palette below.
    fileprivate init(_ start: UInt32, _ end: UInt32) {
        self.init(start: PosterRGB(hex: start), end: PosterRGB(hex: end))
    }
}

/// Chooses a deterministic fallback gradient for a concert with no artwork.
public enum PosterGradient {

    /// A fixed, ordered spread of warm/moody two-stop gradients, carried over
    /// from the prototype (`docs/ideas/on-tour-poster-layouts.html`). Order is
    /// load-bearing: ``index(for:)`` reduces modulo `palette.count`, so
    /// reordering or resizing this array repaints existing shows.
    public static let palette: [PosterGradientPair] = [
        PosterGradientPair(0xC65A2E, 0x7D1F3D),
        PosterGradientPair(0x245B7A, 0x101A52),
        PosterGradientPair(0x8A6A3A, 0x3A2140),
        PosterGradientPair(0x6D2F6A, 0x241246),
        PosterGradientPair(0x2F5A8A, 0x151A3A),
        PosterGradientPair(0xB0632A, 0x4A1D22),
        PosterGradientPair(0x7A5A1F, 0x20183A),
    ]

    /// Canonical 64-bit FNV-1a hash (offset basis `0xcbf29ce484222325`, prime
    /// `0x100000001b3`, XOR-then-multiply per byte). Deterministic across runs
    /// and devices — this is why the seed is not `String.hashValue`.
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// The palette index for a concert: the fold of `"<slug>-<id>"` reduced
    /// modulo the palette size.
    public static func index(for concert: Concert) -> Int {
        Int(fnv1a("\(concert.venue.slug)-\(concert.id)") % UInt64(palette.count))
    }

    /// The fallback gradient for a concert. Stable per concert.
    public static func pair(for concert: Concert) -> PosterGradientPair {
        palette[index(for: concert)]
    }
}
