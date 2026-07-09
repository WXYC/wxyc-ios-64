//
//  OnTourRowBadge.swift
//  WXYC
//
//  Compact "on tour" indicator shown on a playlist row when the played artist
//  has an upcoming Triangle-area show. The feed-scale counterpart to the full
//  Box Office ticket in the detail view — venue + status tag, amber when the show
//  is attendable, muted when it isn't. Matches the prototype's feed-row stub
//  (docs/ideas/touring-shows-box-office.html).
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI

struct OnTourRowBadge: View {
    let show: UpcomingShow

    private var presenter: BoxOfficeTicketPresenter { BoxOfficeTicketPresenter(show) }

    /// Amber (the "on tour" accent, distinct from the green on-air signal) when
    /// the show is attendable; muted white for sold-out / cancelled so the feed
    /// doesn't entice toward a show you can't get into.
    private var isAvailable: Bool {
        show.status == .onSale || show.status == .free
    }

    private var tint: Color {
        isAvailable ? Color(hex: 0xFFC79A) : .white.opacity(0.6)
    }

    private var fill: Color {
        isAvailable ? Color(hex: 0xFF8940).opacity(0.16) : .white.opacity(0.1)
    }

    private var stroke: Color {
        isAvailable ? Color(hex: 0xFF8940).opacity(0.4) : .white.opacity(0.2)
    }

    /// "Cat's Cradle · Tickets", dropping the venue when it's unknown.
    private var label: String {
        [show.venueName, presenter.feedTagText]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "ticket.fill")
                .font(.caption2)
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(fill))
        .overlay(Capsule().stroke(stroke, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("On tour: \(label)")
    }
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

#Preview("On sale") {
    ZStack {
        LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        OnTourRowBadge(show: .init(
            id: 1, eventName: "Nilüfer Yanya", artist: "Nilüfer Yanya",
            venueName: "Cat's Cradle", date: .now, status: .onSale
        ))
    }
}

#Preview("Sold out") {
    ZStack {
        LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        OnTourRowBadge(show: .init(
            id: 2, eventName: "Juana Molina", artist: "Juana Molina",
            venueName: "Motorco", date: .now, status: .soldOut
        ))
    }
}
