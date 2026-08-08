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
//  Three chips keep a solid fill instead. Two had no stroke to adopt at all
//  (the stub's on-sale and free) — already solid "go" chips. The third, the
//  Box Office ticket's on-sale, is a deliberate exemption: it was a solid 1.0
//  fill behind a 0.5 stroke, so it is the one place the rule would *remove*
//  presence, and it is the ticket's primary CTA.
//
//  Ink is chosen for contrast, not for hue. Every chip clears WCAG AA (4.5:1)
//  against its own fill, enforced by `StatusPillSurfacePaletteTests`. In
//  practice that means white on the translucent fills, which is nearly all of
//  them, and dark ink on the three solid light ones — the ticket's on-sale CTA
//  and the stub's on-sale and free. Do not "unify" those three to white; it
//  would put white on a light fill and is the one change this table's test
//  exists to stop.
//
//  The canon table in ``StatusPill`` stays the default and stays tested; it is
//  simply no longer what these three surfaces render. Anything adopting
//  ``StatusPill`` from here on gets canon unless it opts into a surface below.
//
//  Created by Jake Bromberg on 08/07/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import WXUI

/// The `(fill, ink)` pairs for the three surfaces that render status chips, each
/// filled with its former stroke color. Chips have no outline — ``StatusPill``
/// has no border to draw, so that is structural rather than per-surface.
///
/// The three differ from each other on purpose: the feed row and the ticket were
/// tuned against different backgrounds, and two entries track the
/// wallpaper theme, which a static table cannot express. Keying every function
/// on `StatusPill.Style` (rather than each surface's own enum) means the call
/// sites can convert once through `StatusPillStyleMapping` and pass the result
/// straight through.
enum StatusPillSurfacePalette {
    /// `ConcertRow`'s feed tag, over the wallpaper-backed list. On-sale is amber
    /// here, not the canon green: the feed's job is to distinguish rows from
    /// each other, and the Box Office ticket's green already means "on sale" one
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
            (Palette.soldout.opacity(0.5), .white)
        case .negative:
            (Palette.cancel.opacity(0.55), .white)
        case .caution:
            (accent.opacity(0.5), .white)
        case .free:
            (Palette.free.opacity(0.5), .white)
        case .neutral:
            (.white.opacity(0.3), .white)
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
            (.white.opacity(0.25), .white)
        case .negative:
            (Palette.cancel.opacity(0.5), .white)
        case .caution, .neutral:
            (.white.opacity(0.2), .white)
        }
    }

    /// The prototype-derived status colors the ticket and stub share. Expressed
    /// in HSL so the hue relationships read at a glance; trailing hex is the
    /// prototype value.
    private enum Palette {
        static let ok = Color(HSL(hue: 0.3753, saturation: 0.5857, lightness: 0.4922)) // #34C759
        /// Dark, like ``freeText`` and for the same reason: `ok` is the one solid,
        /// bright fill on the ticket, so its ink has to go down to be legible, not up.
        static let okInk = Color(HSL(hue: 0.3753, saturation: 0.85, lightness: 0.09))
        static let soldout = Color(HSL(hue: 0.0405, saturation: 1, lightness: 0.7098)) // #FF8F6B
        static let cancel = Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)) // #FF6B6B
        static let free = Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)) // #4FD6C8
        static let freeText = Color(HSL(hue: 0.4811, saturation: 0.8462, lightness: 0.102)) // #04302B
    }
}
