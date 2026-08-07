//
//  StatusPillSurfacePalette.swift
//  WXYC
//
//  The per-surface status-chip palettes. Each chip is its pre-consolidation
//  original with one transformation applied: **the fill takes the stroke's
//  color, and the stroke is removed.** Hues are exactly the originals — only
//  how much of the hue shows changes, from the wash's opacity to the stroke's.
//
//  This is the change the chips were meant to get. ``StatusPill`` instead
//  collapsed four hand-maintained (fill, border, ink) switches into one canon
//  table, which moved hues that had been deliberately different per surface —
//  most visibly the On Tour feed's "TICKETS" chip, rotated 99° from amber to
//  the canon green. These tables hand each surface its own hues back, and apply
//  the fill/stroke transformation on top.
//
//  Four chips keep a solid fill instead. Three had no stroke to adopt at all
//  (the poster hero's on-sale, and the stub's on-sale and free) — already solid
//  "go" chips. The fourth, the Box Office ticket's on-sale, is a deliberate
//  exemption: it was a solid 1.0 fill behind a 0.5 stroke, so it is the one
//  place the rule would *remove* presence, and it is the ticket's primary CTA.
//
//  The canon table in ``StatusPill`` stays the default and stays tested; it is
//  simply no longer what these four surfaces render. Anything adopting
//  ``StatusPill`` from here on gets canon unless it opts into a surface below.
//
//  Created by Jake Bromberg on 08/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import WXUI

/// The `(fill, ink)` pairs for the four surfaces that render status chips, each
/// filled with its former stroke color. Chips have no outline — ``StatusPill``
/// has no border to draw, so that is structural rather than per-surface.
///
/// The four differ from each other on purpose: the feed row and the poster hero
/// were tuned against different backgrounds, and two entries track the
/// wallpaper theme, which a static table cannot express. Keying every function
/// on `StatusPill.Style` (rather than each surface's own enum) means the call
/// sites can convert once through `StatusPillStyleMapping` and pass the result
/// straight through.
enum StatusPillSurfacePalette {
    /// `ConcertRow`'s feed tag, over the wallpaper-backed list. On-sale is amber
    /// here, not the canon green: the feed's job is to distinguish rows from
    /// each other, and the poster hero's green already means "on sale" one
    /// screen deeper. Fills were 0.1–0.18 washes behind 0.25–0.5 strokes; each
    /// now carries its own stroke's opacity.
    ///
    /// `FeedTagStyle` has no `caution` case — rescheduled folds into `.neutral`,
    /// as it already did upstream.
    static func onTourFeedRow(
        _ style: StatusPill.Style
    ) -> (fill: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color.orange.opacity(0.5), Color(red: 1.0, green: 0.78, blue: 0.6))
        case .free:
            (Color.teal.opacity(0.5), Color(red: 0.72, green: 0.94, blue: 0.91))
        case .muted:
            (Color.white.opacity(0.3), Color.white.opacity(0.7))
        case .negative:
            (Color.red.opacity(0.5), Color(red: 1.0, green: 0.7, blue: 0.7))
        case .caution, .neutral:
            (Color.white.opacity(0.25), Color.white.opacity(0.8))
        }
    }

    /// `ConcertDetailView`'s hero pill, over the poster. Heavier than the feed's
    /// because it sits on artwork rather than on the list's darkened wallpaper.
    /// `.prominent` was already a solid unstroked chip and is unchanged.
    static func concertPosterHero(
        _ style: StatusPill.Style
    ) -> (fill: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.92), Color(red: 0.03, green: 0.19, blue: 0.10))
        case .free:
            (Color.teal.opacity(0.5), Color(red: 0.72, green: 0.94, blue: 0.91))
        case .muted:
            (Color(red: 1.0, green: 0.56, blue: 0.42).opacity(0.5), Color(red: 1.0, green: 0.78, blue: 0.71))
        case .negative:
            (Color.red.opacity(0.55), Color(red: 1.0, green: 0.7, blue: 0.7))
        case .caution:
            (Color.orange.opacity(0.5), Color(red: 1.0, green: 0.78, blue: 0.6))
        case .neutral:
            (.white.opacity(0.3), .white.opacity(0.8))
        }
    }

    /// `BoxOfficeTicketView`'s pill. Deliberately NOT theme-derived except for
    /// `.caution` (rescheduled): on-sale green, sold-out coral, cancelled red,
    /// and free teal read as universal signals across every wallpaper, while
    /// only the ticket's accent chrome follows the theme (see `TicketColors`).
    /// Translated from the prototype's CSS into HSL so the hue relationships
    /// read at a glance; the trailing hex is the prototype value.
    ///
    /// - Parameter accent: the theme's `accentInkColor`, for the one entry that
    ///   tracks the wallpaper.
    static func boxOfficeTicket(
        _ style: StatusPill.Style,
        accent: Color
    ) -> (fill: Color, ink: Color) {
        switch style {
        case .prominent:
            // Exempt from the rule below: this was already a solid 1.0 fill,
            // and it is the ticket's primary CTA chip — adopting the 0.5 stroke
            // would be the one place this transformation *removes* presence.
            (Palette.ok, Palette.okInk)
        case .muted:
            (Palette.soldout.opacity(0.5), Palette.soldoutInk)
        case .negative:
            (Palette.cancel.opacity(0.55), Palette.cancelInk)
        case .caution:
            (accent.opacity(0.5), accent)
        case .free:
            (Palette.free.opacity(0.5), Palette.freeInk)
        case .neutral:
            (.white.opacity(0.3), .white.opacity(0.72))
        }
    }

    /// `OnTourRowBadge`'s stub tag. `.prominent` and `.free` were already solid
    /// unstroked "go" chips and are unchanged; sold-out and cancelled stay
    /// muted so the feed doesn't entice toward a show you can't attend.
    ///
    /// - Parameters:
    ///   - accent: the theme's `accentInkColor` — the "go" chip matches the
    ///     themed `BoxOfficeTicketView` CTA below it.
    ///   - accentInk: the stub's derived dark `buttonInk` for that chip.
    static func playcutStub(
        _ style: StatusPill.Style,
        accent: Color,
        accentInk: Color
    ) -> (fill: Color, ink: Color) {
        switch style {
        case .prominent:
            (accent, accentInk)
        case .free:
            (Palette.free, Palette.freeText)
        case .muted:
            (.white.opacity(0.25), .white.opacity(0.72))
        case .negative:
            (Palette.cancel.opacity(0.5), Palette.cancelInk)
        case .caution, .neutral:
            (.white.opacity(0.2), .white.opacity(0.7))
        }
    }

    /// The prototype-derived status colors the ticket and stub share. Expressed
    /// in HSL so the hue relationships read at a glance; trailing hex is the
    /// prototype value.
    private enum Palette {
        static let ok = Color(HSL(hue: 0.3753, saturation: 0.5857, lightness: 0.4922)) // #34C759
        static let okInk = Color(HSL(hue: 0.3851, saturation: 0.7115, lightness: 0.7961)) // #A6F0BD
        static let soldout = Color(HSL(hue: 0.0405, saturation: 1, lightness: 0.7098)) // #FF8F6B
        static let soldoutInk = Color(HSL(hue: 0.0422, saturation: 1, lightness: 0.8529)) // #FFC7B4
        static let cancel = Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)) // #FF6B6B
        static let cancelInk = Color(HSL(hue: 0, saturation: 1, lightness: 0.851)) // #FFB3B3
        static let free = Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)) // #4FD6C8
        static let freeInk = Color(HSL(hue: 0.4762, saturation: 0.6512, lightness: 0.8314)) // #B8F0E8
        static let freeText = Color(HSL(hue: 0.4811, saturation: 0.8462, lightness: 0.102)) // #04302B
    }
}
