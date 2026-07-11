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
//  colored tag: amber on sale, teal free, dimmed sold-out, red cancelled.
//  Mirrors the prototype's `.rstub` (docs/ideas/touring-shows-box-office.html).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import Playlist
import SwiftUI

struct OnTourRowBadge: View {
    let show: Concert

    /// The stub panel's height. ``PlaycutRowView`` frames the stub to this value
    /// and places the ticket's perforation notches at the seam it defines.
    static let preferredHeight: CGFloat = 34

    private var presenter: BoxOfficeTicketPresenter { BoxOfficeTicketPresenter(show) }

    var body: some View {
        HStack(spacing: 10) {
            // Date — amber mono, like the prototype's `.rk` ("FRI JUL 10").
            Text(presenter.compactDateLabel)
                .font(.system(.caption2, design: .monospaced))
                .fontWeight(.heavy)
                .kerning(0.6)
                .foregroundStyle(Palette.amberInk)
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
                .stroke(Palette.perforation, style: StrokeStyle(lineWidth: 1.5))
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

    /// Tag fill / border / ink per ``FeedTagStyle`` — amber and teal read as solid
    /// "go" chips; sold-out and cancelled are translucent and muted so the feed
    /// doesn't entice toward a show you can't attend.
    private var tagColors: (fill: Color, border: Color, ink: Color) {
        switch presenter.feedTagStyle {
        case .prominent:
            return (Palette.amber, .clear, Palette.onDark)
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

/// The stub's palette, translated from the prototype's CSS tokens into HSL so the
/// hue relationships read at a glance: `amber` and `amberInk` are one hue at two
/// lightnesses, `onDark` is that same amber pushed nearly black, and both cancel
/// tones sit at pure red (hue 0). Trailing hex is the original prototype value.
/// File-private so it doesn't leak into the app-wide color system.
private enum Palette {
    static let amber = Color(HSL(hue: 0.0637, saturation: 1, lightness: 0.6255)) // #FF8940
    static let amberInk = Color(HSL(hue: 0.0743, saturation: 1, lightness: 0.802)) // #FFC79A
    static let free = Color(HSL(hue: 0.4827, saturation: 0.6221, lightness: 0.5745)) // #4FD6C8
    static let freeText = Color(HSL(hue: 0.4811, saturation: 0.8462, lightness: 0.102)) // #04302B
    static let cancel = Color(HSL(hue: 0, saturation: 1, lightness: 0.7098)) // #FF6B6B
    static let cancelInk = Color(HSL(hue: 0, saturation: 1, lightness: 0.851)) // #FFB3B3
    static let perforation = Color.white.opacity(0.28)
    static let onDark = Color(HSL(hue: 0.0794, saturation: 1, lightness: 0.0824)) // #2A1400
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

/// Sits the stub over a translucent dark panel that stands in for the ticket's
/// shared material, on a WXYC-like gradient, so the tag colors and tear line read.
private struct OnTourRowStubPreview: View {
    let status: ShowStatus
    let venue: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.25, green: 0.28, blue: 0.56), Color(red: 0.69, green: 0.24, blue: 0.47)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            OnTourRowBadge(show: .init(
                id: 4821,
                venue: Venue(id: 1, slug: "venue", name: venue, city: "Carrboro", state: "NC", address: nil),
                startsOn: .now,
                headliningArtistRaw: "Nilüfer Yanya",
                status: status
            ))
            .frame(height: OnTourRowBadge.preferredHeight)
            .background(.black.opacity(0.28))
            .clipShape(.rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
            .padding()
        }
    }
}
