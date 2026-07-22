//
//  ForYouShelfView.swift
//  WXYC
//
//  The pinned "Heard on WXYC" recommendation rail (#493): a horizontal row of
//  compact cards above the On Tour date list, rendered only when the on-device
//  match produced at least one card. Loved cards (a liked artist headlines) lead,
//  followed by station-recommended cards, ranked and capped by the pure
//  `ForYouShelf` engine. The cards are deliberately header-only — no per-card tier
//  badge or "reason line": the section header ("Heard on WXYC") is the whole
//  provenance the shelf claims, so it states airplay as a fact rather than dressing
//  each card as a taste prediction. Every recommendation is computed on the device
//  from the local likes store — no taste signal reaches the server — and this view
//  only renders what that engine returned.
//
//  Card taps route to the same detail as a list row via an `onSelect` closure.
//  The cards deliberately do NOT register a `matchedTransitionSource`: the shelf
//  duplicates shows that also appear in the list below (the locked H2 treatment),
//  and the list row already owns `concert.id` in the zoom namespace — a second
//  source for the same id would make the zoom transition ambiguous.
//
//  Created by Jake Bromberg on 07/19/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import SwiftUI
import Wallpaper

/// The horizontal For You rail shown above the On Tour list.
struct ForYouShelfView: View {
    let recommendations: [ForYouRecommendation]
    /// Invoked with the tapped recommendation so the tab can present the detail
    /// and record the tier-only analytics event.
    let onSelect: (ForYouRecommendation) -> Void
    /// Invoked when the listener picks "Not interested" on a card, so the tab can
    /// record it in the dismissed-concerts store and drop the card.
    let onDismiss: (ForYouRecommendation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recommendations) { recommendation in
                        ForYouCard(
                            recommendation: recommendation,
                            action: { onSelect(recommendation) },
                            onDismiss: { onDismiss(recommendation) }
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .accessibilityIdentifier("forYouShelf")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                Text("Heard on WXYC")
                    .font(.system(.subheadline, design: .rounded)).fontWeight(.semibold)
            }
            .foregroundStyle(.white.opacity(0.85))
            .accessibilityAddTraits(.isHeader)
            // The only explanatory copy left on the shelf now that the cards are
            // header-only: names the honest provenance in plain words.
            Text("Artists our DJs played, coming to the Triangle")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 16)
    }
}

// MARK: - Card

/// One compact For You card: poster (or deterministic gradient fallback), date,
/// headliner, and venue. Header-only — no tier badge or reason line; the section
/// header carries the shelf's whole provenance.
private struct ForYouCard: View {
    let recommendation: ForYouRecommendation
    let action: () -> Void
    let onDismiss: () -> Void

    private let presenter: BoxOfficeTicketPresenter

    private var concert: Concert { recommendation.concert }

    private static let cardWidth: CGFloat = 168
    private static let posterHeight: CGFloat = 96

    init(recommendation: ForYouRecommendation, action: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.recommendation = recommendation
        self.action = action
        self.onDismiss = onDismiss
        self.presenter = BoxOfficeTicketPresenter(recommendation.concert)
    }

    var body: some View {
        // The tap `Button` and the overflow `Menu` are siblings in a `ZStack`, not
        // a Menu nested in the Button's label: a control inside a Button's label
        // never receives its own taps, and `onTapGesture` is disallowed here. The
        // menu is drawn above, pinned to the poster's top-trailing corner.
        ZStack(alignment: .topTrailing) {
            Button(action: action) {
                VStack(alignment: .leading, spacing: 0) {
                    poster
                    info
                }
                .frame(width: Self.cardWidth)
                .background(BackgroundLayer(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
                .clipShape(.rect(cornerRadius: 14))
                // A cancelled show reads "dead", matching the list row.
                .saturation(presenter.isCancelled ? 0.4 : 1)
                .opacity(presenter.isCancelled ? 0.7 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            // VoiceOver reaches dismissal through a rotor action, since the visual
            // overflow menu is a separate, small hit target.
            .accessibilityAction(named: "Not interested", onDismiss)
            .accessibilityIdentifier("forYouCard.\(concert.id)")

            overflowMenu
        }
    }

    // MARK: Overflow menu

    /// The top-trailing "•••" control. The visible glass circle stays 24pt, but its
    /// tap target is padded out to 44pt — the app's interactive-target minimum (cf.
    /// `LikeHeartButton`) — so a near-miss doesn't fall through to the full-card
    /// navigation button beneath it.
    private var overflowMenu: some View {
        Menu {
            Button("Not interested", systemImage: "hand.thumbsdown", role: .destructive, action: onDismiss)
        } label: {
            Image(systemName: "ellipsis")
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.black.opacity(0.4)))
                .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .padding(10)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More options for \(concert.headlineName)")
        .accessibilityIdentifier("forYouCard.\(concert.id).overflow")
    }

    // MARK: Poster

    private var poster: some View {
        let pair = PosterGradient.pair(for: concert)
        let gradient = LinearGradient(
            colors: [Color(pair.start), Color(pair.end)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        return Group {
            if let url = concert.imageURL {
                AsyncImage(url: url) { image in
                    // Pins the reported size to the frame so an oversized
                    // landscape poster can't blow out the fixed card width
                    // (see `PosterArt.fillClipped`).
                    PosterArt.fillClipped(image.resizable().scaledToFill())
                } placeholder: {
                    gradient
                }
            } else {
                gradient
            }
        }
        .frame(width: Self.cardWidth, height: Self.posterHeight)
        .clipped()
    }

    // MARK: Info

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presenter.compactDateLabel)
                .font(.system(.caption2, design: .monospaced)).kerning(0.6)
                .foregroundStyle(.white.opacity(0.6))
            Text(concert.headlineName)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(.white)
                // The headliner is the card's only variable-height row; reserving
                // both lines keeps every card on the shelf the same height.
                .lineLimit(2, reservesSpace: true)
            Text(concert.venue.name)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var accessibilityLabel: String {
        [concert.headlineName, concert.venue.name, presenter.dateLabel]
            .joined(separator: ", ")
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    let cradle = Venue(id: 3, slug: "cats-cradle", name: "Cat's Cradle", city: "Carrboro", state: "NC", address: nil)
    let motorco = Venue(id: 7, slug: "motorco", name: "Motorco", city: "Durham", state: "NC", address: nil)
    let loved = Concert(id: 1, venue: cradle, startsOn: Date(timeIntervalSince1970: 1_785_898_800),
                        headliningArtistRaw: "Stereolab", headliningArtistId: 41,
                        ticketURL: URL(string: "https://example.com/a"), status: .onSale)
    let station = Concert(id: 2, venue: motorco, startsOn: Date(timeIntervalSince1970: 1_786_071_600),
                          headliningArtistRaw: "Chuquimamani-Condori", headliningArtistId: 88,
                          ticketURL: URL(string: "https://example.com/b"), status: .onSale)
    // A headliner long enough to wrap to two lines, so the preview shows the
    // short-name cards matching its height.
    let wrapping = Concert(id: 3, venue: cradle, startsOn: Date(timeIntervalSince1970: 1_786_244_400),
                           headliningArtistRaw: "Duke Ellington & John Coltrane", headliningArtistId: 12,
                           ticketURL: URL(string: "https://example.com/c"), status: .onSale)
    let recommendations = [
        ForYouRecommendation(concert: loved, tier: .loved),
        ForYouRecommendation(concert: station, tier: .stationRecommended),
        ForYouRecommendation(concert: wrapping, tier: .stationRecommended),
    ]
    return ZStack {
        LinearGradient(
            colors: [Color(red: 0.25, green: 0.28, blue: 0.55), Color(red: 0.6, green: 0.24, blue: 0.44)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        ForYouShelfView(recommendations: recommendations, onSelect: { _ in }, onDismiss: { _ in })
    }
}
#endif
