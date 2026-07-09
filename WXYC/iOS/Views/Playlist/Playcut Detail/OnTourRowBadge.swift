//
//  OnTourRowBadge.swift
//  WXYC
//
//  The feed-row "stub": a torn ticket strip that hangs beneath a playlist row
//  when the played artist has an upcoming Triangle-area show. The compact
//  counterpart to the full Box Office ticket in the detail view — a perforated
//  top edge with corner punch-outs, then date · venue · status tag across one
//  line. State-colored tag (amber on sale, teal free, dimmed sold-out, red
//  cancelled). Matches the prototype's `.rstub` (docs/ideas/touring-shows-box-office.html).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI

struct OnTourRowBadge: View {
    let show: UpcomingShow

    private var presenter: BoxOfficeTicketPresenter { BoxOfficeTicketPresenter(show) }

    private let cornerRadius: CGFloat = 12
    private let notchRadius: CGFloat = 5

    private var stubShape: RowStubShape {
        RowStubShape(cornerRadius: cornerRadius, notchRadius: notchRadius)
    }

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
            Text(show.venueName ?? "Live Show")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            tag
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background {
            glassSurface(stubShape)
            Color.white.opacity(0.05)
        }
        .clipShape(stubShape)
        .overlay(alignment: .top) {
            // The tear line, inset past the corner punch-outs.
            DashedLine()
                .stroke(Palette.perforation, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(height: 1.5)
                .padding(.horizontal, notchRadius)
        }
        // Cancelled reads as "dead" by desaturating the whole stub, matching the ticket.
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
        [show.venueName, presenter.compactDateLabel, presenter.feedTagText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// A neutral frosted-glass surface: real Liquid Glass on OS 26,
    /// `.ultraThinMaterial` as a fallback. Matches the detail ticket's stub.
    @ViewBuilder
    private func glassSurface<S: Shape>(_ shape: S) -> some View {
        if #available(iOS 26, macOS 26, tvOS 26, watchOS 26, *) {
            shape.fill(.clear).glassEffect(.clear, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

// MARK: - Shapes

/// A ticket-stub outline: square top corners, rounded bottom, and a circular
/// punch-out cut into each top corner so the strip reads as torn from the row
/// above (the wallpaper shows through the cuts). Mirrors the prototype's
/// `.rstub` radius + `::before/::after` notches.
private struct RowStubShape: Shape {
    let cornerRadius: CGFloat
    let notchRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: 0
        ).path(in: rect)

        let diameter = notchRadius * 2
        let left = Path(ellipseIn: CGRect(
            x: rect.minX - notchRadius, y: rect.minY - notchRadius,
            width: diameter, height: diameter
        ))
        let right = Path(ellipseIn: CGRect(
            x: rect.maxX - notchRadius, y: rect.minY - notchRadius,
            width: diameter, height: diameter
        ))
        path = path.subtracting(left).subtracting(right)
        return path
    }
}

/// A single horizontal line across the middle of its rect (the dashed tear line).
private struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

// MARK: - Palette

/// The stub's palette, translated from the prototype's CSS tokens. File-private
/// so it doesn't leak into the app-wide color system.
private enum Palette {
    static let amber = Color(hex: 0xFF8940)
    static let amberInk = Color(hex: 0xFFC79A)
    static let free = Color(hex: 0x4FD6C8)
    static let freeText = Color(hex: 0x04302B)
    static let cancel = Color(hex: 0xFF6B6B)
    static let cancelInk = Color(hex: 0xFFB3B3)
    static let perforation = Color.white.opacity(0.25)
    static let onDark = Color(hex: 0x2A1400)
}

private extension Color {
    /// Builds an sRGB color from a `0xRRGGBB` literal.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
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

/// Stacks a mock row over the stub on a WXYC-like gradient so the tear line and
/// corner punch-outs read against a busy background.
private struct OnTourRowStubPreview: View {
    let status: ShowStatus
    let venue: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x40498E), Color(hex: 0xAF3E79), Color(hex: 0xB64949)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.15))
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Method Actor").fontWeight(.bold)
                        Text("Nilüfer Yanya")
                        Text("9:12 PM").font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                    Spacer()
                }
                .padding(12)

                OnTourRowBadge(show: .init(
                    id: 4821, eventName: "Nilüfer Yanya", artist: "Nilüfer Yanya",
                    venueName: venue, date: .now, status: status
                ))
            }
            .padding()
        }
    }
}
