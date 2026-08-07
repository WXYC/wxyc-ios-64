//
//  StatusPillSurfacePaletteTests.swift
//  WXYC
//
//  Pins each On Tour status-chip surface to the palette it carried before the
//  shared canon table — the four hand-maintained (fill, border, ink) switches
//  that `StatusPill`'s one table replaced. The expected triples below are
//  transcribed from the pre-consolidation sources rather than re-derived from
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

    // MARK: - On Tour feed row (was ConcertRow.tagColors)

    private static func expectedFeedRow(
        _ style: StatusPill.Style
    ) -> (fill: Color, border: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color.orange.opacity(0.18), Color.orange.opacity(0.5), Color(red: 1.0, green: 0.78, blue: 0.6))
        case .free:
            (Color.teal.opacity(0.18), Color.teal.opacity(0.5), Color(red: 0.72, green: 0.94, blue: 0.91))
        case .muted:
            (Color.white.opacity(0.1), Color.white.opacity(0.3), Color.white.opacity(0.7))
        case .negative:
            (Color.red.opacity(0.18), Color.red.opacity(0.5), Color(red: 1.0, green: 0.7, blue: 0.7))
        case .caution, .neutral:
            (Color.white.opacity(0.1), Color.white.opacity(0.25), Color.white.opacity(0.8))
        }
    }

    @Test(
        "the On Tour feed row restores ConcertRow's original palette",
        arguments: StatusPill.Style.allCases
    )
    func feedRowMatchesOriginal(style: StatusPill.Style) {
        #expect(
            Self.resolved(StatusPillSurfacePalette.onTourFeedRow(style))
                == Self.resolved(Self.expectedFeedRow(style))
        )
    }

    // MARK: - Concert poster hero (was ConcertDetailView.pillColors)

    private static func expectedPosterHero(
        _ style: StatusPill.Style
    ) -> (fill: Color, border: Color, ink: Color) {
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
            (.white.opacity(0.14), .white.opacity(0.3), .white.opacity(0.8))
        }
    }

    @Test(
        "the concert poster hero restores ConcertDetailView's original palette",
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
            (Color(HSL(hue: 0.3753, saturation: 0.5857, lightness: 0.4922)).opacity(1.0),
             Color(HSL(hue: 0.3753, saturation: 0.5857, lightness: 0.4922)).opacity(0.5),
             Color(HSL(hue: 0.3851, saturation: 0.7115, lightness: 0.7961)))
        case .muted:
            (Color(HSL(hue: 0.0405, saturation: 1, lightness: 0.7098)).opacity(0.18),
             Color(HSL(hue: 0.0405, saturation: 1, lightness: 0.7098)).opacity(0.5),
             Color(HSL(hue: 0.0422, saturation: 1, lightness: 0.8529)))
        case .negative:
            (Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)).opacity(0.20),
             Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)).opacity(0.55),
             Color(HSL(hue: 0, saturation: 1, lightness: 0.851)))
        case .caution:
            (accent.opacity(0.18), accent.opacity(0.5), accent)
        case .free:
            (Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)).opacity(0.18),
             Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)).opacity(0.5),
             Color(HSL(hue: 0.4762, saturation: 0.6512, lightness: 0.8314)))
        case .neutral:
            (.white.opacity(0.12), .white.opacity(0.3), .white.opacity(0.72))
        }
    }

    @Test(
        "the Box Office ticket restores BoxOfficeTicketView's original palette",
        arguments: StatusPill.Style.allCases
    )
    func boxOfficeMatchesOriginal(style: StatusPill.Style) {
        #expect(
            Self.resolved(StatusPillSurfacePalette.boxOfficeTicket(style, accent: Self.accent))
                == Self.resolved(Self.expectedBoxOffice(style, accent: Self.accent))
        )
    }

    // MARK: - Playcut stub (was OnTourRowBadge.tagColors)

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
            (.white.opacity(0.12), .white.opacity(0.25), .white.opacity(0.72))
        case .negative:
            (Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)).opacity(0.2),
             Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)).opacity(0.5),
             Color(HSL(hue: 0, saturation: 1, lightness: 0.851)))
        case .caution, .neutral:
            (.white.opacity(0.1), .white.opacity(0.2), .white.opacity(0.7))
        }
    }

    @Test(
        "the playcut stub restores OnTourRowBadge's original palette",
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

    // MARK: - The regression this restores

    /// The change that started this: the feed's "TICKETS" chip was rotated 99°
    /// from amber to the canon green when the four switches collapsed into one
    /// table. It is amber again, and specifically *not* the canon green.
    @Test("the feed's on-sale chip is amber, not the canon green")
    func feedProminentIsAmberNotCanonGreen() {
        let feed = Self.resolved(StatusPillSurfacePalette.onTourFeedRow(.prominent))
        let canon = Self.resolved(StatusPill.palette(for: .prominent))

        #expect(feed[0] == Self.resolved((Color.orange.opacity(0.18), .clear, .clear))[0])
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
        #expect(Self.deviatesFromCanon(StatusPillSurfacePalette.onTourFeedRow))
        #expect(Self.deviatesFromCanon(StatusPillSurfacePalette.concertPosterHero))
        #expect(Self.deviatesFromCanon { StatusPillSurfacePalette.boxOfficeTicket($0, accent: Self.accent) })
        #expect(Self.deviatesFromCanon { StatusPillSurfacePalette.playcutStub($0, accent: Self.accent, accentInk: Self.accentInk) })
    }

    private static func deviatesFromCanon(
        _ palette: (StatusPill.Style) -> (fill: Color, border: Color, ink: Color)
    ) -> Bool {
        StatusPill.Style.allCases.contains { style in
            resolved(palette(style)) != resolved(StatusPill.palette(for: style))
        }
    }
}
