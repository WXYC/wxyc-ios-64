//
//  StatusPillTests.swift
//  WXUI
//
//  Tests over StatusPill's palette table and style resolution — the pure logic
//  behind the chrome, since the rendered view itself isn't inspectable without a
//  snapshot/inspection dependency this package deliberately doesn't take on.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI
import Testing
@testable import WXUI

@Suite("StatusPill")
@MainActor
struct StatusPillTests {
    private static var environment: EnvironmentValues { EnvironmentValues() }

    /// The canon palette, kept independent of `StatusPill.palette(for:)` so a
    /// mutation in the production switch is actually caught rather than the test
    /// re-deriving the same values from the same source.
    private static func expectedPalette(for style: StatusPill.Style) -> (fill: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.92), Color(red: 0.03, green: 0.19, blue: 0.10))
        case .free:
            (Color(red: 0.310, green: 0.839, blue: 0.784).opacity(0.92), Color(red: 0.016, green: 0.188, blue: 0.169))
        case .muted:
            (Color(red: 1.0, green: 0.56, blue: 0.42).opacity(0.92), Color(red: 0.24, green: 0.08, blue: 0.03))
        case .negative:
            (Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.92), Color(red: 0.26, green: 0.03, blue: 0.03))
        case .caution:
            (Color(red: 1.0, green: 0.65, blue: 0.20).opacity(0.92), Color(red: 0.24, green: 0.13, blue: 0.01))
        case .neutral:
            (Color(red: 0.82, green: 0.85, blue: 0.89).opacity(0.92), Color(red: 0.11, green: 0.13, blue: 0.16))
        }
    }

    @Test("palette(for:) resolves the canon pair for every style", arguments: StatusPill.Style.allCases)
    func paletteMatchesCanon(style: StatusPill.Style) {
        let resolved = StatusPill.palette(for: style)
        let expected = Self.expectedPalette(for: style)
        #expect(resolved.fill.resolve(in: Self.environment) == expected.fill.resolve(in: Self.environment))
        #expect(resolved.ink.resolve(in: Self.environment) == expected.ink.resolve(in: Self.environment))
    }

    @Test("distinct styles resolve to distinct fills")
    func stylesAreDistinguishable() {
        let fills = StatusPill.Style.allCases.map {
            StatusPill.palette(for: $0).fill.resolve(in: Self.environment)
        }
        for i in fills.indices {
            for j in fills.indices where i != j {
                #expect(fills[i] != fills[j], "styles \(StatusPill.Style.allCases[i]) and \(StatusPill.Style.allCases[j]) share a fill")
            }
        }
    }

    @Test("resolvedPalette falls back to the canon table when no override is supplied")
    func resolvedPaletteUsesCanonByDefault() {
        let resolved = StatusPill.resolvedPalette(style: .free, override: nil)
        let expected = StatusPill.palette(for: .free)
        #expect(resolved.fill.resolve(in: Self.environment) == expected.fill.resolve(in: Self.environment))
        #expect(resolved.ink.resolve(in: Self.environment) == expected.ink.resolve(in: Self.environment))
    }

    @Test("resolvedPalette prefers an explicit override over the canon table")
    func resolvedPaletteHonorsOverride() {
        let override = (fill: Color.purple, ink: Color.yellow)
        let resolved = StatusPill.resolvedPalette(style: .free, override: override)
        #expect(resolved.fill.resolve(in: Self.environment) == override.fill.resolve(in: Self.environment))
        #expect(resolved.ink.resolve(in: Self.environment) == override.ink.resolve(in: Self.environment))
        // And it must differ from the canon table it's overriding, or the
        // assertions above would pass by coincidence rather than by resolution.
        let canon = StatusPill.palette(for: .free)
        #expect(resolved.fill.resolve(in: Self.environment) != canon.fill.resolve(in: Self.environment))
    }

    /// The design rule the canon table exists to enforce: differentiation is
    /// carried by hue alone, never by fill weight — so a "free" show can't end
    /// up looking as unreachable as a sold-out one. Before this, only
    /// `.prominent` was solid and the other five were 18–24% washes.
    ///
    /// The companion "no outline" half of this rule is no longer asserted here:
    /// `StatusPill` has no border to draw, so it is structural rather than
    /// testable.
    @Test("every canon style is a solid fill", arguments: StatusPill.Style.allCases)
    func canonStylesAreSolid(style: StatusPill.Style) {
        #expect(
            StatusPill.palette(for: style).fill.resolve(in: Self.environment).opacity >= 0.9,
            "\(style) fill is a wash, not a solid"
        )
    }

    /// Solid fills need dark ink to stay legible; the old translucent styles
    /// used light ink over a dark surface. A style that kept light ink after the
    /// switch to solid fills would be near-invisible.
    @Test("every canon style pairs its solid fill with dark ink", arguments: StatusPill.Style.allCases)
    func canonInkIsDark(style: StatusPill.Style) {
        let ink = StatusPill.palette(for: style).ink.resolve(in: Self.environment)
        let luminance = 0.2126 * Double(ink.red) + 0.7152 * Double(ink.green) + 0.0722 * Double(ink.blue)
        #expect(luminance < 0.3, "\(style) ink is too light to read on a solid fill (luminance \(luminance))")
    }

    @Test("canon mechanics match the ticket: padding 10/4, kerning 1")
    func canonMechanics() {
        #expect(StatusPill.horizontalPadding == 10)
        #expect(StatusPill.verticalPadding == 4)
        #expect(StatusPill.kerning == 1)
    }
}
