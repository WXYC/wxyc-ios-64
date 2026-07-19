//
//  ForYouShelfView.swift
//  WXYC
//
//  The pinned "For You" recommendation rail (#493): a horizontal row of compact
//  cards above the On Tour date list, rendered only when the on-device match
//  produced at least one card. Loved cards (a liked artist headlines) lead with a
//  filled-heart accent; similar cards ("Because you like X") follow, ranked and
//  capped by the pure `ForYouShelf` engine. Every recommendation is computed on
//  the device from the local likes store — no taste signal reaches the server —
//  and this view only renders what that engine returned.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(recommendations) { recommendation in
                        ForYouCard(recommendation: recommendation) { onSelect(recommendation) }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .accessibilityIdentifier("forYouShelf")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
            Text("For You")
                .font(.system(.subheadline, design: .rounded)).fontWeight(.semibold)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 16)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Card

/// One compact For You card: poster (or deterministic gradient fallback), date,
/// headliner, venue, and the tier reason line.
private struct ForYouCard: View {
    let recommendation: ForYouRecommendation
    let action: () -> Void

    private let presenter: BoxOfficeTicketPresenter

    private var concert: Concert { recommendation.concert }

    private static let cardWidth: CGFloat = 168
    private static let posterHeight: CGFloat = 96

    init(recommendation: ForYouRecommendation, action: @escaping () -> Void) {
        self.recommendation = recommendation
        self.action = action
        self.presenter = BoxOfficeTicketPresenter(recommendation.concert)
    }

    var body: some View {
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
    }

    // MARK: Poster

    private var poster: some View {
        let pair = PosterGradient.pair(for: concert)
        let gradient = LinearGradient(
            colors: [Color(pair.start), Color(pair.end)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        return ZStack(alignment: .topLeading) {
            Group {
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

            tierBadge.padding(8)
        }
        .frame(width: Self.cardWidth, height: Self.posterHeight)
    }

    private var tierBadge: some View {
        let style = badgeStyle
        return Image(systemName: style.symbol)
            .font(.caption).fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(style.fill))
            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
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
                .lineLimit(2)
            Text(concert.venue.name)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            reasonRow
                .padding(.top, 2)
        }
        .frame(width: Self.cardWidth, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }

    private var reasonRow: some View {
        let reason = reasonStyle
        return HStack(spacing: 4) {
            Image(systemName: reason.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(reason.tint)
            Text(reasonText)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    /// The reason copy shown on the card and read by VoiceOver. A single source
    /// so the visible line and the accessibility label can't drift apart.
    private var reasonText: String {
        switch recommendation.tier {
        // The headliner (already the card title) is itself a liked artist — don't
        // restate the name, just mark it as loved.
        case .loved: "In your likes"
        case .similar: "Because you like \(recommendation.reasonArtistName)"
        // Station affinity has no personal tie to name — the reason is the
        // station-wide signal itself.
        case .stationAffinity: "Heavy rotation on WXYC"
        }
    }

    // MARK: Tier styling

    /// The poster badge: a vivid pink heart for loved (a strong, unambiguous
    /// signal) versus a muted glass sparkle for similar — the two tiers must not
    /// read as the same confidence (`touring-soon-reco-highlights.html`).
    private var badgeStyle: (symbol: String, fill: Color) {
        switch recommendation.tier {
        case .loved:
            (symbol: "heart.fill", fill: LikeHeartButton.likeColor)
        case .similar:
            (symbol: "sparkles", fill: Color.black.opacity(0.35))
        case .stationAffinity:
            (symbol: "antenna.radiowaves.left.and.right", fill: Color.black.opacity(0.35))
        }
    }

    /// The reason line's icon and tint. The copy itself comes from ``reasonText``.
    private var reasonStyle: (symbol: String, tint: Color) {
        switch recommendation.tier {
        case .loved: (symbol: "heart.fill", tint: LikeHeartButton.likeColor)
        case .similar: (symbol: "sparkles", tint: Color.white.opacity(0.6))
        case .stationAffinity: (symbol: "antenna.radiowaves.left.and.right", tint: Color.white.opacity(0.6))
        }
    }

    private var accessibilityLabel: String {
        [concert.headlineName, reasonText, concert.venue.name, presenter.dateLabel]
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
    let similar = Concert(id: 2, venue: motorco, startsOn: Date(timeIntervalSince1970: 1_786_071_600),
                          headliningArtistRaw: "Broadcast", headliningArtistId: 88,
                          ticketURL: URL(string: "https://example.com/b"), status: .onSale)
    let recommendations = [
        ForYouRecommendation(concert: loved, tier: .loved, reasonArtistName: "Stereolab"),
        ForYouRecommendation(concert: similar, tier: .similar(weight: 0.82), reasonArtistName: "Stereolab"),
    ]
    return ZStack {
        LinearGradient(
            colors: [Color(red: 0.25, green: 0.28, blue: 0.55), Color(red: 0.6, green: 0.24, blue: 0.44)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        ForYouShelfView(recommendations: recommendations) { _ in }
    }
}
#endif
