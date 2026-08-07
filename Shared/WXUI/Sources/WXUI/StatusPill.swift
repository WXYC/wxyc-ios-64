//
//  StatusPill.swift
//  WXUI
//
//  A solid-filled, monospaced status chip: one palette table shared by every
//  "state" tag in the app (On Tour feed rows, the Box Office ticket, the concert
//  poster hero) instead of four independently hand-maintained (fill, border, ink)
//  switches. Canon mechanics — padding, stroke width, font, kerning — are fixed;
//  only the color triple varies per ``Style``, and only via the shared table
//  unless a caller has a genuine reason (a theme-derived accent, say) to supply
//  its own via `paletteOverride`.
//
//  Every canon style is a solid fill with no outline — see ``palette(for:)``
//  for why the earlier solid/translucent split was collapsed.
//
//  NOTE: the four On Tour surfaces that prompted this type all pass a
//  `paletteOverride` — consolidating their colors moved hues that were tuned
//  per surface, so `StatusPillSurfacePalette` (app target) hands each one its
//  original triple back. What they still share from here is the *mechanics*:
//  padding, stroke width, font, kerning. The canon table below remains the
//  default for anything adopting this type fresh.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import SwiftUI

/// A small stroked capsule showing an uppercased status word — "ON SALE",
/// "SOLD OUT", "FREE", and so on.
///
/// The color triple for each ``Style`` lives in one canon table
/// (``palette(for:)``); callers select a semantic style rather than choosing
/// colors themselves. A caller whose chip must track something the table can't
/// know about — a theme-derived accent color, for instance — may supply
/// `paletteOverride` to replace the resolved triple for that one instance. The
/// override replaces colors only: padding, stroke width, font, and kerning
/// stay canon everywhere.
public struct StatusPill: View {
    /// The semantic state a pill communicates. Shared by every adopting
    /// surface so "on sale" (etc.) means the same color everywhere by default.
    public enum Style: Sendable, Equatable, CaseIterable {
        /// The most actionable state — tickets on sale, a show worth pointing at.
        case prominent
        /// A free or RSVP show.
        case free
        /// Sold out, or otherwise dimmed-but-still-linked.
        case muted
        /// Cancelled, or another "this fell through" state.
        case negative
        /// Rescheduled, or another "check the details" state.
        case caution
        /// Unknown, or no state worth calling out.
        case neutral
    }

    /// Horizontal padding inside the capsule. Canon: 10pt.
    public static let horizontalPadding: CGFloat = 10
    /// Vertical padding inside the capsule. Canon: 4pt.
    public static let verticalPadding: CGFloat = 4
    /// The capsule stroke's line width. Canon: 1pt.
    public static let strokeWidth: CGFloat = 1
    /// Tracking applied to the uppercased text. Canon: 1.
    public static let kerning: CGFloat = 1

    let text: String
    let style: Style
    let paletteOverride: (fill: Color, border: Color, ink: Color)?

    /// - Parameters:
    ///   - text: The label, upper-cased for display. Callers pass natural case
    ///     ("On Sale"); the pill uppercases it.
    ///   - style: The semantic state selecting a row from the canon palette.
    ///   - paletteOverride: An explicit `(fill, border, ink)` triple to use
    ///     instead of the canon table's row for `style`. Reserved for cases
    ///     that must track something the static table can't express, such as
    ///     a theme-derived accent color — flag the reason at the call site.
    public init(
        text: String,
        style: Style,
        paletteOverride: (fill: Color, border: Color, ink: Color)? = nil
    ) {
        self.text = text
        self.style = style
        self.paletteOverride = paletteOverride
    }

    public var body: some View {
        let colors = Self.resolvedPalette(style: style, override: paletteOverride)
        Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.bold)
            .kerning(Self.kerning)
            .foregroundStyle(colors.ink)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(Capsule().fill(colors.fill))
            .overlay(Capsule().stroke(colors.border, lineWidth: Self.strokeWidth))
            .fixedSize()
    }

    /// The color triple to render: `override` when supplied, otherwise the
    /// canon table's row for `style`. Exposed as a pure function (rather than
    /// inlined in `body`) so the resolution rule itself — override wins,
    /// canon is the fallback — is directly testable.
    static func resolvedPalette(
        style: Style,
        override: (fill: Color, border: Color, ink: Color)?
    ) -> (fill: Color, border: Color, ink: Color) {
        override ?? palette(for: style)
    }

    /// The single canon palette table. Every adopting surface reads its
    /// colors from here by default — this is the "ONE palette table" the
    /// four hand-maintained switches collapsed into.
    ///
    /// **Every style is a solid fill with no outline**, the way "on sale" has
    /// always read. Differentiation is carried by hue alone, never by fill
    /// weight. The earlier table made only `.prominent` solid and rendered the
    /// other five as 18–24% washes behind a stroke, which sorted the chips into
    /// two visual families — "solid = act on this" and "translucent = don't
    /// bother" — and put FREE in the second one. A free show is among the most
    /// actionable rows in the feed, so the two-family split is gone: a chip's
    /// state is its color, and its weight never varies.
    ///
    /// Fills sit at 0.92 rather than 1.0 so a chip settles onto the ticket
    /// material it's printed on instead of floating above it. Inks are dark
    /// members of each fill's own hue — a solid chip needs dark ink, which is
    /// why the old light inks moved with the fills rather than staying put.
    ///
    /// `border` stays in the triple because a `paletteOverride` caller may
    /// still want one; no canon style uses it.
    public static func palette(for style: Style) -> (fill: Color, border: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color(red: 0.20, green: 0.78, blue: 0.35).opacity(0.92), .clear, Color(red: 0.03, green: 0.19, blue: 0.10))
        case .free:
            // #4FD6C8 over #04302B — the stub's original free teal, restored.
            (Color(red: 0.310, green: 0.839, blue: 0.784).opacity(0.92), .clear, Color(red: 0.016, green: 0.188, blue: 0.169))
        case .muted:
            (Color(red: 1.0, green: 0.56, blue: 0.42).opacity(0.92), .clear, Color(red: 0.24, green: 0.08, blue: 0.03))
        case .negative:
            (Color(red: 1.0, green: 0.42, blue: 0.42).opacity(0.92), .clear, Color(red: 0.26, green: 0.03, blue: 0.03))
        case .caution:
            (Color(red: 1.0, green: 0.65, blue: 0.20).opacity(0.92), .clear, Color(red: 0.24, green: 0.13, blue: 0.01))
        case .neutral:
            (Color(red: 0.82, green: 0.85, blue: 0.89).opacity(0.92), .clear, Color(red: 0.11, green: 0.13, blue: 0.16))
        }
    }
}
