//
//  StatusPill.swift
//  WXUI
//
//  A stroked, monospaced status chip: one palette table shared by every "state"
//  tag in the app (On Tour feed rows, the Box Office ticket, the concert poster
//  hero) instead of four independently hand-maintained (fill, border, ink)
//  switches. Canon mechanics — padding, stroke width, font, kerning — are fixed;
//  only the color triple varies per ``Style``, and only via the shared table
//  unless a caller has a genuine reason (a theme-derived accent, say) to supply
//  its own via `paletteOverride`.
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
    public static func palette(for style: Style) -> (fill: Color, border: Color, ink: Color) {
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
}
