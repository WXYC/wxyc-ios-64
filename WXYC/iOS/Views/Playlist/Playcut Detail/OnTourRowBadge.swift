//
//  OnTourRowBadge.swift
//  WXYC
//
//  The feed-row "stub": the lower panel of a playlist row's ticket, shown when
//  the played artist has an upcoming Triangle-area show. Draws only the strip's
//  contents — date · venue · status tag on one line, plus a dashed tear line
//  along the top seam. The surrounding ``PlaycutRowView`` supplies the shared
//  wallpaper background and the perforated ticket outline (the semicircle
//  punch-outs at the seam), so this view never draws its own surface. State-
//  colored tag: the theme accent for on-sale, teal free, dimmed sold-out, red
//  cancelled — the date and tag tint with the theme (see ``TicketColors``), so the
//  stub stays consistent with ``BoxOfficeTicketView`` and its discovery CTA.
//  Mirrors the prototype's `.rstub` (docs/ideas/touring-shows-box-office.html).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Playlist
import SwiftUI
import Wallpaper

struct OnTourRowBadge: View {
    let show: Concert
    let colors: TicketColors

    /// The stub panel's height. ``PlaycutRowView`` frames the stub to this value
    /// and places the ticket's perforation notches at the seam it defines.
    static let preferredHeight: CGFloat = 34

    private var presenter: BoxOfficeTicketPresenter { BoxOfficeTicketPresenter(show) }

    /// Dark, accent-tinted ink for the light `accentInkColor`-filled "go" tag —
    /// matches ``BoxOfficeTicketView``'s CTA. The body ink is always light, so this
    /// reads.
    private var buttonInk: Color {
        let ink = colors.bodyInk.components
        return Color(hue: ink.hue / 360, saturation: min(1, ink.saturation + 0.15), brightness: 0.16)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Date — accent mono, like the prototype's `.rk` ("FRI JUL 10").
            Text(presenter.compactDateLabel)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.heavy)
                .kerning(0.6)
                .foregroundStyle(colors.accentInkColor)
                .fixedSize()

            // Venue — takes the middle, truncating before it crowds the tag.
            Text(show.venue.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            tag
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: Self.preferredHeight)
        .overlay(alignment: .top) {
            // The tear line, inset horizontally so it clears the corner punch-outs.
            DashedLine()
                .stroke(colors.perforationColor, style: StrokeStyle(lineWidth: 1.5))
                .frame(height: 1.5)
                .padding(.horizontal, 10)
        }
        // Cancelled reads as "dead" by desaturating the strip, matching the ticket.
        .saturation(presenter.feedTagStyle == .negative ? 0.4 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// The state-colored status tag on the right (`.rtag`).
    private var tag: some View {
        let colors = tagColors
        return Text(presenter.feedTagText.uppercased())
            .font(.system(size: 10, weight: .heavy))
            .kerning(0.5)
            .foregroundStyle(colors.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(colors.fill))
            .overlay(Capsule().stroke(colors.border, lineWidth: colors.border == .clear ? 0 : 0.75))
            .fixedSize()
    }

    /// Tag fill / border / ink per ``FeedTagStyle`` — the theme accent and teal
    /// read as solid "go" chips; sold-out and cancelled are translucent and muted
    /// so the feed doesn't entice toward a show you can't attend.
    private var tagColors: (fill: Color, border: Color, ink: Color) {
        switch presenter.feedTagStyle {
        case .prominent:
            return (colors.accentInkColor, .clear, buttonInk)
        case .free:
            return (Palette.free, .clear, Palette.freeText)
        case .muted:
            return (.white.opacity(0.12), .white.opacity(0.25), .white.opacity(0.72))
        case .negative:
            return (Palette.cancel.opacity(0.2), Palette.cancel.opacity(0.5), Palette.cancelInk)
        case .neutral:
            return (.white.opacity(0.1), .white.opacity(0.2), .white.opacity(0.7))
        }
    }

    private var accessibilityText: String {
        [show.venue.name, presenter.compactDateLabel, presenter.feedTagText]
            .joined(separator: ", ")
    }
}

// MARK: - Palette

/// The stub's **status** palette — free teal and cancelled red stay universal
/// across every theme; the accent-colored "go" tag, the date, and the perforation
/// now tint with the wallpaper (see ``TicketColors``). Translated from the
/// prototype's CSS into HSL; trailing hex is the prototype value. File-private.
private enum Palette {
    static let free = Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)) // #4FD6C8
    static let freeText = Color(HSL(hue: 0.4811, saturation: 0.8462, lightness: 0.102)) // #04302B
    static let cancel = Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)) // #FF6B6B
    static let cancelInk = Color(HSL(hue: 0, saturation: 1, lightness: 0.851)) // #FFB3B3
}

// MARK: - Previews

#Preview("On sale") {
    OnTourRowStubPreview(status: .onSale, venue: "Cat's Cradle")
}

#Preview("Free") {
    OnTourRowStubPreview(status: .free, venue: "Nightlight")
}

#Preview("Sold out") {
    OnTourRowStubPreview(status: .soldOut, venue: "Motorco Music Hall")
}

#Preview("Cancelled") {
    OnTourRowStubPreview(status: .cancelled, venue: "Local 506")
}

#Preview("Rescheduled") {
    OnTourRowStubPreview(status: .rescheduled, venue: "The Pinhook")
}

#Preview("Unknown") {
    OnTourRowStubPreview(status: .unknown, venue: "Kings")
}

/// Sits the stub over a translucent dark panel that stands in for the ticket's
/// shared material, on a WXYC-like gradient, so the tag colors and tear line read.
private struct OnTourRowStubPreview: View {
    let status: ShowStatus
    let venue: String
    var colors: TicketColors = .previewPlasticPulse

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.25, green: 0.28, blue: 0.56), Color(red: 0.69, green: 0.24, blue: 0.47)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            OnTourRowBadge(
                show: .init(
                    id: 4821,
                    venue: Venue(id: 1, slug: "venue", name: venue, city: "Carrboro", state: "NC", address: nil),
                    startsOn: .now,
                    headliningArtistRaw: "Nilüfer Yanya",
                    status: status
                ),
                colors: colors
            )
            .frame(height: OnTourRowBadge.preferredHeight)
            .background(.black.opacity(0.28))
            .clipShape(.rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
            .padding()
        }
    }
}

/// An authored ticket sample so the preview matches on-device, now that the palette
/// is fully authored (nothing derived from the accent). A teal keepsake (like The
/// Plastic Pulse) over a dark wallpaper.
private extension TicketColors {
    static let previewPlasticPulse = TicketColors.resolve(
        foreground: .light,
        manifest: TicketPalette(
            bodyTop: HSBAlpha(hue: 185, saturation: 0.45, brightness: 0.32, alpha: 0.52),
            bodyBottom: HSBAlpha(hue: 190, saturation: 0.55, brightness: 0.20, alpha: 0.60),
            stub: HSBAlpha(hue: 185, saturation: 0.22, brightness: 0.92, alpha: 0.12),
            bodyInk: HSBAlpha(hue: 185, saturation: 0.20, brightness: 1.00, alpha: 1),
            edge: HSBAlpha(hue: 185, saturation: 0.50, brightness: 0.85, alpha: 0.48)
        ),
        override: nil
    )
}
