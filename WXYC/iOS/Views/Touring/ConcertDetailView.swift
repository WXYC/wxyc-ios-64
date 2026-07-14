//
//  ConcertDetailView.swift
//  WXYC
//
//  The On Tour event detail: a poster-first destination that the tapped row
//  zooms into (`.navigationTransition(.zoom)`), replacing the barren
//  ticket-on-a-gradient sheet. A full-bleed hero (real `image_url` when present,
//  a deterministic `PosterGradient` fallback otherwise) carries the artist and
//  date; the shipped Box Office ticket tucks under the poster's bottom edge as
//  the keepsake and the outbound CTA; a compact "Where" block offers directions.
//
//  Implements the approved prototype docs/ideas/on-tour-poster-layouts.html,
//  layout B2 (Tucked Ticket), with the full Box Office ticket as the card.
//
//  Created by Jake Bromberg on 07/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import SwiftUI
import Wallpaper

/// The poster-first detail for a single ``Concert``.
struct ConcertDetailView: View {
    let concert: Concert

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// The active theme, source of the ticket's wallpaper-derived colors. Set at
    /// the app root; propagates into this `.fullScreenCover` presentation.
    @Environment(Singletonia.self) private var appState

    /// Built once — the concert is immutable for the lifetime of the detail.
    private let presenter: BoxOfficeTicketPresenter

    init(concert: Concert) {
        self.concert = concert
        self.presenter = BoxOfficeTicketPresenter(concert)
    }

    // Poster geometry. The ticket is pulled up by `ticketTuck` so it straddles
    // the seam between the poster and the dark body below.
    private let posterHeight: CGFloat = 420
    private let ticketTuck: CGFloat = 28

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                posterHero
                VStack(spacing: 20) {
                    BoxOfficeTicketView(show: concert, colors: appState.themeConfiguration.effectiveTicketColors)
                    whereSection
                }
                .padding(.horizontal, 16)
                .padding(.top, -ticketTuck)
                .padding(.bottom, 40)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Self.backdrop.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .overlay(alignment: .topLeading) { backButton }
    }

    // MARK: - Poster hero

    private var posterHero: some View {
        ZStack(alignment: .bottomLeading) {
            posterArt
            posterInitial
            Self.heroScrim
            heroContent
        }
        .frame(height: posterHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    /// Real artwork when the concert carries an `image_url`; otherwise the
    /// deterministic gradient fallback (the common case today).
    @ViewBuilder
    private var posterArt: some View {
        let pair = PosterGradient.pair(for: concert)
        let gradient = LinearGradient(
            colors: [Color(pair.start), Color(pair.end)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        if let url = concert.imageURL {
            AsyncImage(url: url) { image in
                Self.fillClipped(image.resizable().scaledToFill())
            } placeholder: {
                gradient
            }
        } else {
            gradient
        }
    }

    /// Bounds oversized fill artwork to the poster frame. `scaledToFill` reports a
    /// size *larger* than the proposal for any aspect ratio that doesn't match the
    /// box — a landscape poster fitted to the hero height reports a width wider
    /// than the screen. That oversized width escapes `.clipped()` (which clips
    /// drawing, not layout) and blows out the hero's width, bleeding the whole
    /// scroll content past both screen edges. Drawing the fill over a
    /// `Color.clear` — which reports exactly the proposed size — pins the reported
    /// size back to the frame while the trailing `.clipped()` trims the overflow.
    fileprivate static func fillClipped<Content: View>(_ content: Content) -> some View {
        Color.clear.overlay { content }.clipped()
    }

    /// The oversized, faint artist initial behind the hero text — a poster
    /// flourish carried over from the prototype.
    private var posterInitial: some View {
        Text(String(concert.headlineName.prefix(1)))
            .font(.system(size: 260, weight: .black))
            .foregroundStyle(.white.opacity(0.09))
            .offset(x: 40, y: -30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .accessibilityHidden(true)
    }

    private var heroContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let pill = presenter.statusPillText {
                statusPill(pill)
            }
            Text(concert.headlineName)
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.5), radius: 12, y: 3)
            Text(presenter.heroCreditLine)
                .font(.system(.footnote, design: .monospaced))
                .kerning(0.5)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Where

    private var whereSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHERE")
                .font(.system(.caption2, design: .monospaced))
                .kerning(1.6)
                .foregroundStyle(.white.opacity(0.45))

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(concert.venue.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(venueAddressLine)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 8)
                if let url = presenter.directionsURL {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "location.fill").font(.caption)
                            Text("Directions")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(.white.opacity(0.16)))
                        .overlay(Capsule().stroke(.white.opacity(0.22), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Directions to \(concert.venue.name)")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.06), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Street address when the venue carries one, else the city and state.
    private var venueAddressLine: String {
        if let address = concert.venue.address, !address.isEmpty {
            return "\(address) · \(concert.venue.city)"
        }
        return "\(concert.venue.city), \(concert.venue.state)"
    }

    // MARK: - Chrome

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.ultraThinMaterial, in: .circle)
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.leading, 14)
        .padding(.top, 54)
        .accessibilityLabel("Back")
    }

    private func statusPill(_ text: String) -> some View {
        let colors = Self.pillColors(presenter.statusPillStyle)
        return Text(text.uppercased())
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.bold)
            .kerning(1)
            .foregroundStyle(colors.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(colors.fill))
            .overlay(Capsule().stroke(colors.border, lineWidth: 1))
            .fixedSize()
    }

    // MARK: - Palette

    /// The dark backdrop the poster sits over — the detail reads as a "moment",
    /// not the app's translucent wallpaper surface (matches the prototype's
    /// `--page` background).
    private static let backdrop = Color(red: 0.063, green: 0.055, blue: 0.102)

    /// A bottom-weighted scrim so the hero text reads over any artwork.
    private static let heroScrim = LinearGradient(
        stops: [
            .init(color: .black.opacity(0.30), location: 0.0),
            .init(color: .black.opacity(0.0), location: 0.32),
            .init(color: .black.opacity(0.55), location: 0.78),
            .init(color: backdrop.opacity(0.95), location: 1.0),
        ],
        startPoint: .top, endPoint: .bottom
    )

    /// Maps a semantic ``StatusPillStyle`` to the hero pill's fill / border / ink
    /// triple — the poster counterpart to `ConcertRow`'s `tagColors`, so the
    /// status→style decision stays in the tested presenter and only the palette
    /// lives here.
    private static func pillColors(_ style: StatusPillStyle) -> (fill: Color, border: Color, ink: Color) {
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
}

// MARK: - Color from PosterRGB

private extension Color {
    /// Builds a SwiftUI color from the package's plain-data ``PosterRGB``.
    init(_ rgb: PosterRGB) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("On sale — gradient fallback") {
    ConcertDetailView(concert: .detailPreview(status: .onSale))
        .environment(Singletonia.shared)
}

#Preview("Sold out") {
    ConcertDetailView(concert: .detailPreview(status: .soldOut, headliningArtistRaw: "Jessica Pratt"))
        .environment(Singletonia.shared)
}

#Preview("Free") {
    ConcertDetailView(concert: .detailPreview(status: .free, priceMin: 0, priceMax: 0))
        .environment(Singletonia.shared)
}

#Preview("Cancelled") {
    ConcertDetailView(concert: .detailPreview(status: .cancelled, headliningArtistRaw: "Water From Your Eyes"))
        .environment(Singletonia.shared)
}

// Regression guard for the artwork-overflow bug: a real `image_url` renders via
// `AsyncImage` + `scaledToFill`, which reports a width wider than the screen for a
// landscape poster and used to blow the layout past both edges. `AsyncImage` won't
// fetch in a preview, so this exercises the `fillClipped` wrapper directly with a
// deliberately wide (≈3:1) stand-in. The red border hugs the poster frame when the
// wrapper contains the fill; remove `Color.clear` from `fillClipped` and the
// stand-in bleeds past the border — the same failure the live artwork produced.
#Preview("Wide artwork stays within bounds") {
    ConcertDetailView.fillClipped(
        LinearGradient(colors: [.orange, .purple], startPoint: .leading, endPoint: .trailing)
            .frame(width: 1400, height: 460)
    )
    .frame(height: 420)
    .frame(maxWidth: .infinity)
    .clipped()
    .border(.red)
    .padding()
}

private extension Concert {
    /// A detail-preview concert (no `image_url`, so the gradient fallback shows).
    nonisolated static func detailPreview(
        status: ShowStatus,
        headliningArtistRaw: String = "Nilüfer Yanya",
        priceMin: Double? = 22,
        priceMax: Double? = 25
    ) -> Concert {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .gmt
        let startsOn = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))
            ?? Date(timeIntervalSince1970: 1_785_898_800)
        let doorsAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 19))
        let startsAt = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 20))
        return Concert(
            id: 4821,
            venue: Venue(id: 3, slug: "cats-cradle", name: "Cat's Cradle", city: "Carrboro", state: "NC", address: "300 E Main St"),
            startsOn: startsOn,
            startsAt: startsAt,
            doorsAt: doorsAt,
            headliningArtistRaw: headliningArtistRaw,
            supportingArtistsRaw: ["Tapir!"],
            ticketURL: URL(string: "https://www.etix.com/ticket/p/x"),
            priceMin: priceMin,
            priceMax: priceMax,
            ageRestriction: "All Ages",
            status: status
        )
    }
}
#endif
