//
//  StatusPillSurfacePaletteTests.swift
//  WXYC
//
//  Pins each On Tour status-chip surface to its pre-consolidation palette with
//  one transformation applied: the fill takes the stroke's color and the stroke
//  is removed. Hues are exactly the originals — only the fill's opacity moves,
//  from the wash's value to the stroke's.
//
//  The expected triples below are transcribed from the pre-consolidation
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
        _ triple: (fill: Color, border: Color, ink: Color)
    ) -> [Color.Resolved] {
        let environment = EnvironmentValues()
        return [
            triple.fill.resolve(in: environment),
            triple.border.resolve(in: environment),
            triple.ink.resolve(in: environment),
        ]
    }

    /// Every surface's palette, for parameterising the cross-cutting invariants.
    private typealias SurfacePalette = @MainActor (StatusPill.Style) -> (fill: Color, border: Color, ink: Color)

    private static let allSurfaces: [(name: String, palette: SurfacePalette)] = [
        ("onTourFeedRow", StatusPillSurfacePalette.onTourFeedRow),
        ("concertPosterHero", StatusPillSurfacePalette.concertPosterHero),
        ("boxOfficeTicket", { StatusPillSurfacePalette.boxOfficeTicket($0, accent: accent) }),
        ("playcutStub", { StatusPillSurfacePalette.playcutStub($0, accent: accent, accentInk: accentInk) }),
    ]

    // MARK: - On Tour feed row (was ConcertRow.tagColors)

    /// Original fills were 0.1–0.18 washes behind 0.25–0.5 strokes; each fill
    /// now carries its own stroke's opacity.
    private static func expectedFeedRow(
        _ style: StatusPill.Style
    ) -> (fill: Color, border: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color.orange.opacity(0.5), .clear, Color(red: 1.0, green: 0.78, blue: 0.6))
        case .free:
            (Color.teal.opacity(0.5), .clear, Color(red: 0.72, green: 0.94, blue: 0.91))
        case .muted:
            (Color.white.opacity(0.3), .clear, Color.white.opacity(0.7))
        case .negative:
            (Color.red.opacity(0.5), .clear, Color(red: 1.0, green: 0.7, blue: 0.7))
        case .caution, .neutral:
            (Color.white.opacity(0.25), .clear, Color.white.opacity(0.8))
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

    // MARK: - Concert poster hero (was ConcertDetailView.pillColors)

    /// `.prominent` had no stroke to adopt — it was already a solid, unstroked
    /// chip, so it is unchanged.
    private static func expectedPosterHero(
        _ style: StatusPill.Style
    ) -> (fill: Color, border: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.92), .clear, Color(red: 0.03, green: 0.19, blue: 0.10))
        case .free:
            (Color.teal.opacity(0.5), .clear, Color(red: 0.72, green: 0.94, blue: 0.91))
        case .muted:
            (Color(red: 1.0, green: 0.56, blue: 0.42).opacity(0.5), .clear, Color(red: 1.0, green: 0.78, blue: 0.71))
        case .negative:
            (Color.red.opacity(0.55), .clear, Color(red: 1.0, green: 0.7, blue: 0.7))
        case .caution:
            (Color.orange.opacity(0.5), .clear, Color(red: 1.0, green: 0.78, blue: 0.6))
        case .neutral:
            (.white.opacity(0.3), .clear, .white.opacity(0.8))
        }
    }

    @Test(
        "the concert poster hero fills with its former stroke color",
        arguments: StatusPill.Style.allCases
    )
    func posterHeroMatchesOriginal(style: StatusPill.Style) {
        #expect(
            Self.resolved(StatusPillSurfacePalette.concertPosterHero(style))
                == Self.resolved(Self.expectedPosterHero(style))
        )
    }

    // MARK: - Box Office ticket (was BoxOfficeTicketView.pillColors)

    private static func expectedBoxOffice(
        _ style: StatusPill.Style,
        accent: Color
    ) -> (fill: Color, border: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color(HSL(hue: 0.3753, saturation: 0.5857, lightness: 0.4922)).opacity(0.5),
             .clear,
             Color(HSL(hue: 0.3851, saturation: 0.7115, lightness: 0.7961)))
        case .muted:
            (Color(HSL(hue: 0.0405, saturation: 1, lightness: 0.7098)).opacity(0.5),
             .clear,
             Color(HSL(hue: 0.0422, saturation: 1, lightness: 0.8529)))
        case .negative:
            (Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)).opacity(0.55),
             .clear,
             Color(HSL(hue: 0, saturation: 1, lightness: 0.851)))
        case .caution:
            (accent.opacity(0.5), .clear, accent)
        case .free:
            (Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)).opacity(0.5),
             .clear,
             Color(HSL(hue: 0.4762, saturation: 0.6512, lightness: 0.8314)))
        case .neutral:
            (.white.opacity(0.3), .clear, .white.opacity(0.72))
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
    /// solid, unstroked "go" chips, so both are unchanged.
    private static func expectedPlaycutStub(
        _ style: StatusPill.Style,
        accent: Color,
        accentInk: Color
    ) -> (fill: Color, border: Color, ink: Color) {
        switch style {
        case .prominent:
            (accent, .clear, accentInk)
        case .free:
            (Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)),
             .clear,
             Color(HSL(hue: 0.4811, saturation: 0.8462, lightness: 0.102)))
        case .muted:
            (.white.opacity(0.25), .clear, .white.opacity(0.72))
        case .negative:
            (Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)).opacity(0.5),
             .clear,
             Color(HSL(hue: 0, saturation: 1, lightness: 0.851)))
        case .caution, .neutral:
            (.white.opacity(0.2), .clear, .white.opacity(0.7))
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

    // MARK: - The rule, enforced rather than described

    /// "Remove the stroke, for all chips." No surface may return a visible
    /// border for any style — `StatusPill` still draws the overlay, so a
    /// non-clear border here puts an outline back on screen.
    @Test("no surface draws a stroke, for any style", arguments: StatusPill.Style.allCases)
    func noSurfaceDrawsAStroke(style: StatusPill.Style) {
        let clear = Self.resolved((.clear, .clear, .clear))[0]
        for surface in Self.allSurfaces {
            #expect(
                Self.resolved(surface.palette(style))[1] == clear,
                "\(surface.name) draws a stroke for \(style)"
            )
        }
    }

    /// Hue is preserved: taking the stroke's color changes only how much of it
    /// shows. The feed's on-sale chip stays amber, and stays off the canon
    /// green it had been rotated 99° onto.
    @Test("the feed's on-sale chip is amber, not the canon green")
    func feedProminentIsAmberNotCanonGreen() {
        let feed = Self.resolved(StatusPillSurfacePalette.onTourFeedRow(.prominent))
        let canon = Self.resolved(StatusPill.palette(for: .prominent))

        #expect(feed[0] == Self.resolved((Color.orange.opacity(0.5), .clear, .clear))[0])
        #expect(feed[0] != canon[0], "the feed's on-sale chip is back on the canon green")
    }

    /// The two surfaces that legitimately track the wallpaper theme must keep
    /// doing so — a static table cannot express these, which is why they were
    /// the one deviation the consolidation already preserved.
    @Test("the theme-derived entries track the supplied accent")
    func themeDerivedEntriesTrackAccent() {
        let stub = Self.resolved(
            StatusPillSurfacePalette.playcutStub(.prominent, accent: Self.accent, accentInk: Self.accentInk)
        )
        let ticket = Self.resolved(
            StatusPillSurfacePalette.boxOfficeTicket(.caution, accent: Self.accent)
        )
        let accent = Self.resolved((Self.accent, .clear, .clear))[0]

        #expect(stub[0] == accent)
        #expect(ticket[2] == accent)
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
