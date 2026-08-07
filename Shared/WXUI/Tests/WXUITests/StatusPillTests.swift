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
    private static func expectedPalette(for style: StatusPill.Style) -> (fill: Color, border: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.92), .clear, Color(red: 0.03, green: 0.19, blue: 0.10))
        case .free:
            (Color.teal.opacity(0.20), Color.teal.opacity(0.5), Color(red: 0.72, green: 0.94, blue: 0.91))
        case .muted:
            (Color(red: 1.0, green: 0.56, blue: 0.42).opacity(0.2), Color(red: 1.0, green: 0.56, blue: 0.42).opacity(0.5), Color(red: 1.0, green: 0.78, blue: 0.71))
        case .negative:
            (Color.red.opacity(0.24), Color.red.opacity(0.55), Color(red: 1.0, green: 0.7, blue: 0.7))
        case .caution:
            (Color.orange.opacity(0.18), Color.orange.opacity(0.5), Color(red: 1.0, green: 0.78, blue: 0.6))
        case .neutral:
            (Color.white.opacity(0.14), Color.white.opacity(0.3), Color.white.opacity(0.8))
        }
    }

    @Test("palette(for:) resolves the canon triple for every style", arguments: StatusPill.Style.allCases)
    func paletteMatchesCanon(style: StatusPill.Style) {
        let resolved = StatusPill.palette(for: style)
        let expected = Self.expectedPalette(for: style)
        #expect(resolved.fill.resolve(in: Self.environment) == expected.fill.resolve(in: Self.environment))
        #expect(resolved.border.resolve(in: Self.environment) == expected.border.resolve(in: Self.environment))
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
        #expect(resolved.border.resolve(in: Self.environment) == expected.border.resolve(in: Self.environment))
        #expect(resolved.ink.resolve(in: Self.environment) == expected.ink.resolve(in: Self.environment))
    }

    @Test("resolvedPalette prefers an explicit override over the canon table")
    func resolvedPaletteHonorsOverride() {
        let override = (fill: Color.purple, border: Color.pink, ink: Color.yellow)
        let resolved = StatusPill.resolvedPalette(style: .free, override: override)
        #expect(resolved.fill.resolve(in: Self.environment) == override.fill.resolve(in: Self.environment))
        #expect(resolved.border.resolve(in: Self.environment) == override.border.resolve(in: Self.environment))
        #expect(resolved.ink.resolve(in: Self.environment) == override.ink.resolve(in: Self.environment))
        // And it must differ from the canon table it's overriding, or the
        // assertions above would pass by coincidence rather than by resolution.
        let canon = StatusPill.palette(for: .free)
        #expect(resolved.fill.resolve(in: Self.environment) != canon.fill.resolve(in: Self.environment))
    }

    @Test("canon mechanics match the ticket: padding 10/4, 1pt stroke, kerning 1")
    func canonMechanics() {
        #expect(StatusPill.horizontalPadding == 10)
        #expect(StatusPill.verticalPadding == 4)
        #expect(StatusPill.strokeWidth == 1)
        #expect(StatusPill.kerning == 1)
    }
}
