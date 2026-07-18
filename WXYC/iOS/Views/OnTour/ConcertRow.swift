//
//  ConcertRow.swift
//  WXYC
//
//  A compact, tappable On Tour list row for one `Concert`. Every display
//  string comes from `BoxOfficeTicketPresenter` — the same presenter behind the
//  Box Office ticket — so copy and formatting match the playcut ticket surfaces.
//  Tapping the row opens the full ticket detail.
//
//  Created by Jake Bromberg on 07/13/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Concerts
import SwiftUI
import Wallpaper

/// A single concert row in the On Tour tab's list.
struct ConcertRow: View {
    let concert: Concert
    /// The zoom-transition namespace shared with the detail destination, so the
    /// row is the source the poster detail animates out of.
    let namespace: Namespace.ID
    let action: () -> Void

    /// Built once per row (the row is immutable) rather than recomputed on every
    /// body/subview access.
    private let presenter: BoxOfficeTicketPresenter

    init(concert: Concert, namespace: Namespace.ID, action: @escaping () -> Void) {
        self.concert = concert
        self.namespace = namespace
        self.action = action
        self.presenter = BoxOfficeTicketPresenter(concert)
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 14) {
                dateBlock
                details
                Spacer(minLength: 8)
                feedTag
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The same theme-aware material as the playlist's playcut rows
            // (`BackgroundLayer`), so the two list surfaces match.
            .background(BackgroundLayer(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12), lineWidth: 1))
            .contentShape(.rect(cornerRadius: 12))
            // A cancelled show reads "dead": desaturated and dimmed.
            .saturation(presenter.isCancelled ? 0.4 : 1)
            .opacity(presenter.isCancelled ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .matchedTransitionSource(id: concert.id, in: namespace)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// The stub-style date block: weekday, day number, month stacked.
    private var dateBlock: some View {
        VStack(spacing: 1) {
            Text(presenter.stubWeekday)
                .font(.system(.caption2, design: .monospaced)).kerning(1)
                .foregroundStyle(.white.opacity(0.75))
            Text(presenter.stubDayNumber)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(.white)
            Text(presenter.stubMonth)
                .font(.system(.caption2, design: .monospaced)).kerning(1)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(width: 46)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(concert.headlineName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(venueLine)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            if let detailLine {
                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
    }

    private var venueLine: String {
        "\(concert.venue.name) · \(concert.venue.city)"
    }

    /// Time and/or price, joined, or `nil` when neither is known.
    private var detailLine: String? {
        let pieces = [presenter.timeLabel, presenter.priceLabel].compactMap { $0 }
        return pieces.isEmpty ? nil : pieces.joined(separator: "  ·  ")
    }

    private var feedTag: some View {
        let colors = Self.tagColors(presenter.feedTagStyle)
        return Text(presenter.feedTagText.uppercased())
            .font(.system(.caption2, design: .monospaced)).fontWeight(.bold).kerning(0.8)
            .foregroundStyle(colors.ink)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(colors.fill))
            .overlay(Capsule().stroke(colors.border, lineWidth: 1))
            .fixedSize()
    }

    private var accessibilityLabel: String {
        [concert.headlineName, venueLine, presenter.dateLabel, detailLine, presenter.feedTagText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    /// Maps a semantic feed-tag style to a fill / border / ink triple, echoing the
    /// Box Office ticket's color language (amber for on-sale, teal for free, etc.).
    private static func tagColors(_ style: FeedTagStyle) -> (fill: Color, border: Color, ink: Color) {
        switch style {
        case .prominent:
            (Color.orange.opacity(0.18), Color.orange.opacity(0.5), Color(red: 1.0, green: 0.78, blue: 0.6))
        case .free:
            (Color.teal.opacity(0.18), Color.teal.opacity(0.5), Color(red: 0.72, green: 0.94, blue: 0.91))
        case .muted:
            (Color.white.opacity(0.1), Color.white.opacity(0.3), Color.white.opacity(0.7))
        case .negative:
            (Color.red.opacity(0.18), Color.red.opacity(0.5), Color(red: 1.0, green: 0.7, blue: 0.7))
        case .neutral:
            (Color.white.opacity(0.1), Color.white.opacity(0.25), Color.white.opacity(0.8))
        }
    }
}
