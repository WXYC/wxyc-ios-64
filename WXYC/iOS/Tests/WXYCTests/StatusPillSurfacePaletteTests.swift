//
//  StatusPillSurfacePaletteTests.swift
//  WXYC
//
//  Pins each On Tour status-chip surface to its pre-consolidation palette with
//  one transformation applied: the fill takes the stroke's color and the stroke
//  is removed. Hues are exactly the originals — only the fill's opacity moves,
//  from the wash's value to the stroke's.
//
//  The expected pairs below are transcribed from the pre-consolidation
//  sources and transformed by hand, rather than re-derived from
//  `StatusPillSurfacePalette`, so a mutation in the production switch is caught
//  instead of mirrored.
//
//  Created by Jake Bromberg on 08/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import Testing
import WXUI
@testable import WXYC

@Suite("StatusPillSurfacePalette")
@MainActor
struct StatusPillSurfacePaletteTests {
    /// A distinctive stand-in for the theme's `accentInkColor`, so a surface
    /// that is supposed to track the theme can be told apart from one that
    /// merely happens to sit near it in the canon table.
    private static let accent = Color(red: 0.90, green: 0.30, blue: 0.60)
    /// A stand-in for the stub's derived `buttonInk`.
    private static let accentInk = Color(red: 0.14, green: 0.04, blue: 0.09)

    private static func resolved(
        _ pair: (fill: Color, ink: Color)
    ) -> [Color.Resolved] {
        let environment = EnvironmentValues()
        return [
            pair.fill.resolve(in: environment),
            pair.ink.resolve(in: environment),
        ]
    }

    /// Every surface's palette, for parameterising the cross-cutting invariants.
    private typealias SurfacePalette = @MainActor (StatusPill.Style) -> (fill: Color, ink: Color)

    private static let allSurfaces: [(name: String, palette: SurfacePalette)] = [
        ("onTourFeedRow", StatusPillSurfacePalette.onTourFeedRow),
        ("boxOfficeTicket", { StatusPillSurfacePalette.boxOfficeTicket($0, accent: accent) }),
        ("playcutStub", { StatusPillSurfacePalette.playcutStub($0, accent: accent, accentInk: accentInk) }),
    ]

    // MARK: - Contrast

    /// The darkened panel every chip sits on — `ConcertRow`'s list background,
    /// the ticket body, and the stub's `.black.opacity(0.28)` are all in this
    /// neighbourhood. Translucent fills have to be composited over *something*
    /// to have a luminance at all, and this is the representative case.
    ///
    /// It is deliberately a single backdrop rather than a sweep: the wallpaper
    /// behind it is user-selectable and can be bright, so no fixed pair of
    /// colors is contrast-safe against every theme. What this pins is the ink's
    /// contrast against its own fill in the common, darkened case — which is
    /// what "unreadable chip" means in practice.
    private static let backdrop = Color(red: 0.12, green: 0.12, blue: 0.14)

    /// WCAG 2.1 relative luminance. `Color.Resolved` exposes linear components
    /// directly, so no de-gamma step is needed here.
    private static func luminance(_ c: Color.Resolved) -> Double {
        0.2126 * Double(c.linearRed)
            + 0.7152 * Double(c.linearGreen)
            + 0.0722 * Double(c.linearBlue)
    }

    /// Source-over composite in sRGB space, matching how the layer is actually
    /// blended, then resolved back through `Color` so luminance sees the same
    /// value the display does.
    private static func composite(_ top: Color.Resolved, over bottom: Color.Resolved) -> Color.Resolved {
        let a = Double(top.opacity)
        return Color(
            red: Double(top.red) * a + Double(bottom.red) * (1 - a),
            green: Double(top.green) * a + Double(bottom.green) * (1 - a),
            blue: Double(top.blue) * a + Double(bottom.blue) * (1 - a)
        ).resolve(in: EnvironmentValues())
    }

    /// WCAG 2.1 contrast ratio, `1.0...21.0`.
    private static func contrastRatio(
        _ pair: (fill: Color, ink: Color)
    ) -> Double {
        let environment = EnvironmentValues()
        let base = backdrop.resolve(in: environment)
        let fill = composite(pair.fill.resolve(in: environment), over: base)
        let ink = composite(pair.ink.resolve(in: environment), over: fill)
        let a = luminance(fill), b = luminance(ink)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// WCAG AA for normal-size text. The chips set ~11pt semibold uppercase,
    /// which is under the 14pt-bold "large text" threshold that would let this
    /// drop to 3.0.
    private static let minimumContrast = 4.5

    @Test(
        "every chip's ink clears WCAG AA against its own fill",
        arguments: StatusPill.Style.allCases
    )
    func inkIsHighContrast(style: StatusPill.Style) {
        for surface in Self.allSurfaces {
            let ratio = Self.contrastRatio(surface.palette(style))
            #expect(
                ratio >= Self.minimumContrast,
                "\(surface.name).\(style) contrast \(String(format: "%.2f", ratio)):1 is below \(Self.minimumContrast):1"
            )
        }
    }

    // MARK: - On Tour feed row (was ConcertRow.tagColors)

    /// Original fills were 0.1–0.18 washes behind 0.25–0.5 strokes; each fill
    /// now carries its own stroke's opacity. Inks are plain white: every fill
    /// here is translucent over the darkened list, so white is the
    /// highest-contrast choice on all five.
    private static func expectedFeedRow(
        _ style: StatusPill.Style
    ) -> (fill: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color.orange.opacity(0.5), .white)
        case .free:
            (Color.teal.opacity(0.5), .white)
        case .muted:
            (Color.white.opacity(0.3), .white)
        case .negative:
            (Color.red.opacity(0.5), .white)
        case .caution, .neutral:
            (Color.white.opacity(0.25), .white)
        }
    }

    @Test(
        "the On Tour feed row fills with its former stroke color",
        arguments: StatusPill.Style.allCases
    )
    func feedRowMatchesOriginal(style: StatusPill.Style) {
        #expect(
            Self.resolved(StatusPillSurfacePalette.onTourFeedRow(style))
                == Self.resolved(Self.expectedFeedRow(style))
        )
    }

    // MARK: - Box Office ticket (was BoxOfficeTicketView.pillColors)

    private static func expectedBoxOffice(
        _ style: StatusPill.Style,
        accent: Color
    ) -> (fill: Color, ink: Color) {
        switch style {
        case .prominent:
            // Exempt from the fill-takes-the-stroke rule: already a solid 1.0
            // fill, and the ticket's primary CTA chip. The only ink here that
            // goes *down* rather than white — the fill is solid and bright.
            (Color(HSL(hue: 0.3753, saturation: 0.5857, lightness: 0.4922)),
             Color(HSL(hue: 0.3753, saturation: 0.85, lightness: 0.09)))
        case .muted:
            (Color(HSL(hue: 0.0405, saturation: 1, lightness: 0.7098)).opacity(0.5), .white)
        case .negative:
            (Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)).opacity(0.55), .white)
        case .caution:
            (accent.opacity(0.5), .white)
        case .free:
            (Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)).opacity(0.5), .white)
        case .neutral:
            (.white.opacity(0.3), .white)
        }
    }

    @Test(
        "the Box Office ticket fills with its former stroke color",
        arguments: StatusPill.Style.allCases
    )
    func boxOfficeMatchesOriginal(style: StatusPill.Style) {
        #expect(
            Self.resolved(StatusPillSurfacePalette.boxOfficeTicket(style, accent: Self.accent))
                == Self.resolved(Self.expectedBoxOffice(style, accent: Self.accent))
        )
    }

    // MARK: - Playcut stub (was OnTourRowBadge.tagColors)

    /// `.prominent` and `.free` had no stroke to adopt — both were already
    /// solid, unstroked "go" chips, so both are unchanged. They are also the two
    /// entries that keep dark ink: their fills are solid and light, so going
    /// white would *lower* contrast rather than raise it.
    private static func expectedPlaycutStub(
        _ style: StatusPill.Style,
        accent: Color,
        accentInk: Color
    ) -> (fill: Color, ink: Color) {
        switch style {
        case .prominent:
            (accent, accentInk)
        case .free:
            (Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)),
             Color(HSL(hue: 0.4811, saturation: 0.8462, lightness: 0.102)))
        case .muted:
            (.white.opacity(0.25), .white)
        case .negative:
            (Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)).opacity(0.5), .white)
        case .caution, .neutral:
            (.white.opacity(0.2), .white)
        }
    }

    @Test(
        "the playcut stub fills with its former stroke color",
        arguments: StatusPill.Style.allCases
    )
    func playcutStubMatchesOriginal(style: StatusPill.Style) {
        #expect(
            Self.resolved(
                StatusPillSurfacePalette.playcutStub(style, accent: Self.accent, accentInk: Self.accentInk)
            ) == Self.resolved(
                Self.expectedPlaycutStub(style, accent: Self.accent, accentInk: Self.accentInk)
            )
        )
    }

    // MARK: - Invariants

    /// Hue is preserved: taking the stroke's color changes only how much of it
    /// shows. The feed's on-sale chip stays amber, and stays off the canon
    /// green it had been rotated 99° onto.
    @Test("the feed's on-sale chip is amber, not the canon green")
    func feedProminentIsAmberNotCanonGreen() {
        let feed = Self.resolved(StatusPillSurfacePalette.onTourFeedRow(.prominent))
        let canon = Self.resolved(StatusPill.palette(for: .prominent))

        #expect(feed[0] == Self.resolved((Color.orange.opacity(0.5), .clear))[0])
        #expect(feed[0] != canon[0], "the feed's on-sale chip is back on the canon green")
    }

    /// The two surfaces that legitimately track the wallpaper theme must keep
    /// doing so — a static table cannot express these, which is why they were
    /// the one deviation the consolidation already preserved.
    ///
    /// Both track it through their *fill*. The ticket's `.caution` ink used to
    /// be the accent as well, which made the chip a single hue at two opacities
    /// and left it at 2.22:1 — the worst contrast of any chip. The ink is white
    /// now; the fill is what carries the theme.
    @Test("the theme-derived entries track the supplied accent")
    func themeDerivedEntriesTrackAccent() {
        let stub = Self.resolved(
            StatusPillSurfacePalette.playcutStub(.prominent, accent: Self.accent, accentInk: Self.accentInk)
        )
        let ticket = Self.resolved(
            StatusPillSurfacePalette.boxOfficeTicket(.caution, accent: Self.accent)
        )

        #expect(stub[0] == Self.resolved((Self.accent, .clear))[0])
        #expect(ticket[0] == Self.resolved((Self.accent.opacity(0.5), .clear))[0])
    }

    /// Every surface deviates from the canon table somewhere — otherwise the
    /// override it installs is dead weight and the restoration did nothing.
    @Test("each surface actually deviates from the canon table")
    func eachSurfaceDeviatesFromCanon() {
        for surface in Self.allSurfaces {
            #expect(
                StatusPill.Style.allCases.contains { style in
                    Self.resolved(surface.palette(style)) != Self.resolved(StatusPill.palette(for: style))
                },
                "\(surface.name) matches canon everywhere; its override is dead weight"
            )
        }
    }
}
