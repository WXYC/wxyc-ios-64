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

import Analytics
import Concerts
import SwiftUI
import Wallpaper
import WXUI

/// A single concert row in the On Tour tab's list.
struct ConcertRow: View {
    let concert: Concert
    /// The zoom-transition namespace shared with the detail destination, so the
    /// row is the source the poster detail animates out of.
    let namespace: Namespace.ID
    let action: () -> Void

    @Environment(\.openURL) private var openURL

    /// Non-nil while the row's share sheet is presented; the "Share Show" context
    /// action sets it.
    @State private var shareTarget: Concert?

    /// Set by the "Add to Calendar" context action to kick off the write-only
    /// access request and, on grant, the event editor (see ``addToCalendar(_:surface:)``).
    @State private var calendarTrigger: Concert?

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
        .contextMenu { contextActions }
        .concertShareSheet(concert: $shareTarget)
        .addToCalendar($calendarTrigger, surface: "row")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// The long-press menu: the detail's actions without leaving the list. "Share
    /// Show" opens the same bare-URL share sheet as the detail chrome (see
    /// ``ConcertShareSheet``); tickets and directions open externally.
    @ViewBuilder
    private var contextActions: some View {
        Button {
            StructuredPostHogAnalytics.shared.capture(ConcertShareInitiated(surface: "row"))
            shareTarget = concert
        } label: {
            Label("Share Show", systemImage: "square.and.arrow.up")
        }
        Button {
            calendarTrigger = concert
        } label: {
            Label("Add to Calendar", systemImage: "calendar.badge.plus")
        }
        if let ticketsURL = presenter.ctaURL {
            Button {
                openURL(ticketsURL)
            } label: {
                Label("Get Tickets", systemImage: "ticket")
            }
        }
        if let directionsURL = presenter.directionsURL {
            Button {
                openURL(directionsURL)
            } label: {
                Label("Directions", systemImage: "location.fill")
            }
        }
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
        StatusPill(text: presenter.feedTagText, style: presenter.feedTagStyle.statusPillStyle)
    }

    private var accessibilityLabel: String {
        [concert.headlineName, venueLine, presenter.dateLabel, detailLine, presenter.feedTagText]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
