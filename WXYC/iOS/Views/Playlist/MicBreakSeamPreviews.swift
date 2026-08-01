//
//  MicBreakSeamPreviews.swift
//  WXYC
//
//  Design exploration for the talkset/breakpoint redesign: renames "Talkset" to
//  "mic break" and coalesces a run of adjacent markers into a single centered
//  chip (no hairline). Every seam — mic break, hour boundary, or a coalesced run
//  of both — renders as one pill. Preview-only scaffolding; nothing here is wired
//  into PlaylistView. Flip through the #Preview variants in the canvas and delete
//  this file once the production seam renderer is built.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Playlist
import SwiftUI
import Wallpaper
import WXUI

// MARK: - Seam grammar

/// One seam between songs in the feed, always rendered as a single centered pill
/// (no hairline — the chip floats on the wallpaper as its own punctuation).
/// Between any two songs there is at most one of these, so a run of talksets plus
/// a top-of-hour breakpoint collapses into one chip. The pill's content is
/// additive:
///
/// - Lone breakpoint (an hour boundary with no DJ talk): `[ 3PM ET ]`.
/// - Lone talkset (the DJ talked, not on an hour boundary): `[ 🎙 MIC BREAK ]`.
/// - Coalesced run (talk at the top of the hour): `[ 🎙 MIC BREAK · 3PM ET ]`.
///
/// A run spanning several hour boundaries (a talk block, dead air) collapses to
/// one chip too; the coalescing pass picks a single `hourLabel` — the newest
/// hour, or a pre-formatted span. This view just renders the string it's given.
private struct SeamRow: View {
    var hourLabel: String?
    var micBreak = false

    var body: some View {
        chip
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var chip: some View {
        HStack(spacing: 6) {
            if micBreak {
                Image(systemName: "microphone.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                Text("mic break".uppercased())
                    .font(.system(size: 14, weight: .bold).smallCaps())
                    .foregroundStyle(.white)
            }
            if micBreak, hourLabel != nil {
                Text("·")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            if let hourLabel {
                Text(hourLabel.uppercased())
                    .font(.system(size: 13, weight: .bold).smallCaps())
                    .foregroundStyle(.white)
            }
        }
        .fixedSize()
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            GeometryReader { proxy in
                BackgroundLayer(cornerRadius: proxy.size.height / 2)
            }
        )
    }
}

// MARK: - Feed scaffolding

/// A slice of the playlist feed with real `PlaycutRowView` rows, so the seam
/// variants are judged against the actual card chrome (glass, mesh gradient,
/// like heart). The seam is injected between the newest song and the set below
/// it. `newest`/`recapped` default to the top-of-hour fixture but can be
/// overridden to bracket a multi-hour gap with sensible play times.
private struct SeamPreviewFeed<Seam: View>: View {
    var newest: Playcut = SeamFixtures.newestPlaycut
    var recapped: [Playcut] = SeamFixtures.recappedPlaycuts
    @ViewBuilder let seam: () -> Seam

    /// Zoom-transition namespace the rows need since #373a7e17; unused here (the
    /// preview never presents the detail cover) but required by `PlaycutRowView`.
    @Namespace private var zoomNamespace

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                PlaylistSectionHeader(text: "recently played")
                row(newest)
                seam()
                ForEach(recapped) { row($0) }
            }
        }
        .contentMargins(.horizontal, 12, for: .scrollContent)
        .coordinateSpace(name: "scroll")
        .background(WXYCBackground())
        .environment(Singletonia.shared)
    }

    private func row(_ playcut: Playcut) -> some View {
        PlaycutRowView(playcut: playcut, namespace: zoomNamespace, onSelect: { _ in })
            .padding(.vertical, 8)
    }
}

/// WXYC-canonical fixture data (docs/test-fixtures.md), timed around a 3 PM ET
/// hour boundary: the DJ back-announces two tracks at the top of the hour
/// (station-ID time — which is exactly why talksets and breakpoints cluster),
/// then plays the next song.
private enum SeamFixtures {
    /// 3 PM ET on 2026-07-23. On a Pacific machine `formattedDate` renders the
    /// real dual-zone label ("12PM PT / 3PM ET"), same as listeners see.
    static let hourBoundary = Breakpoint(
        id: 903,
        hour: 1_784_833_200_000,
        chronOrderID: 903,
        timeCreated: 1_784_833_200_000
    )

    /// The song playing after the mic break — 3:04 PM ET.
    static let newestPlaycut = Playcut(
        id: 905,
        hour: 1_784_833_200_000,
        chronOrderID: 905,
        timeCreated: 1_784_833_440_000,
        songTitle: "Back, Baby",
        labelName: "Drag City",
        artistName: "Jessica Pratt",
        releaseTitle: "On Your Own Love Again"
    )

    /// The set the DJ recapped — 2:55 and 2:48 PM ET, below the seam.
    static let recappedPlaycuts = [
        Playcut(
            id: 901,
            hour: 1_784_829_600_000,
            chronOrderID: 901,
            timeCreated: 1_784_832_900_000,
            songTitle: "la paradoja",
            labelName: "Sonamos",
            artistName: "Juana Molina",
            releaseTitle: "DOGA"
        ),
        Playcut(
            id: 900,
            hour: 1_784_829_600_000,
            chronOrderID: 900,
            timeCreated: 1_784_832_480_000,
            songTitle: "Call Your Name",
            labelName: "self-released",
            artistName: "Chuquimamani-Condori",
            releaseTitle: "Edits"
        ),
    ]

    static var hourLabel: String {
        hourBoundary.formattedDate
    }

    // MARK: Multi-hour run

    /// A run of breakpoints with no music between them — e.g. a talk block or
    /// automation gap. Four consecutive top-of-hour boundaries, 3–6 PM ET on
    /// 2026-07-23, ascending so `.last` is the newest hour.
    static let breakpointRun: [Breakpoint] = [
        Breakpoint(id: 910, hour: 1_784_833_200_000, chronOrderID: 910, timeCreated: 1_784_833_200_000),
        Breakpoint(id: 911, hour: 1_784_836_800_000, chronOrderID: 911, timeCreated: 1_784_836_800_000),
        Breakpoint(id: 912, hour: 1_784_840_400_000, chronOrderID: 912, timeCreated: 1_784_840_400_000),
        Breakpoint(id: 913, hour: 1_784_844_000_000, chronOrderID: 913, timeCreated: 1_784_844_000_000),
    ]

    /// The song that resumes play after the gap — 6:10 PM ET. Sits above the run
    /// seam so the feed brackets a real 3–6 PM music gap in reverse-chron.
    static let postGapPlaycut = Playcut(
        id: 915,
        hour: 1_784_844_600_000,
        chronOrderID: 915,
        timeCreated: 1_784_844_600_000,
        songTitle: "In a Sentimental Mood",
        labelName: "Impulse Records",
        artistName: "Duke Ellington & John Coltrane",
        releaseTitle: "Duke Ellington & John Coltrane"
    )

    /// The newest boundary's label — what the recommended collapse shows. Carries
    /// the same dual-zone treatment as every other single-hour chip.
    static var runNewestHourLabel: String {
        breakpointRun.last?.formattedDate ?? ""
    }

    /// A station-time-only span across the run's first and last hours — the
    /// compact form the range variant needs to avoid an unwieldy dual-zone range
    /// ("12PM PT / 3PM ET – 3PM PT / 6PM ET"). The formatting hit: single-hour
    /// chips keep the listener's local zone; this one drops it.
    static var runRangeLabel: String {
        guard let first = breakpointRun.first, let last = breakpointRun.last else { return "" }
        let station = TimeZone(identifier: "America/New_York") ?? .gmt
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = station
        formatter.dateFormat = "ha"
        let start = formatter.string(from: first.broadcastDate)
        let end = formatter.string(from: last.broadcastDate)
        let zone = station.localizedName(for: .shortGeneric, locale: formatter.locale)
            ?? station.abbreviation(for: first.broadcastDate)
            ?? "ET"
        return "\(start)–\(end) \(zone)"
    }
}

// MARK: - Variants

// What ships today: talksets and breakpoints share one pill, and a run
// (double-logged talkset + top-of-hour breakpoint) stacks three identical pills
// between two songs.
#Preview("Before · Today") {
    SeamPreviewFeed {
        VStack(spacing: 0) {
            TextRowView(text: "Talkset")
                .padding(.vertical, 8)
            TextRowView(text: "Talkset")
                .padding(.vertical, 8)
            TextRowView(text: SeamFixtures.hourLabel)
                .padding(.vertical, 8)
        }
    }
}

// The chosen direction: the whole run collapses into a single centered chip that
// carries both the mic break and the hour. No hairline. Between any two songs
// there is at most one seam.
#Preview("C · Coalesced") {
    SeamPreviewFeed {
        SeamRow(hourLabel: SeamFixtures.hourLabel, micBreak: true)
            .padding(.vertical, 8)
    }
}

// The lone-breakpoint case: an hour boundary the DJ passed through without
// talking. Same pill as a mic break, but carrying only the hour — no mic glyph,
// since nothing was said.
#Preview("Hour only · no talk") {
    SeamPreviewFeed {
        SeamRow(hourLabel: SeamFixtures.hourLabel)
            .padding(.vertical, 8)
    }
}

// MARK: - Multi-hour breakpoint run

// The three previews below all represent the SAME underlying run — four adjacent
// breakpoints (3, 4, 5, 6 PM ET) with no music between them, a talk block. The
// feed brackets them with a 6:10 PM song above and the 2:48–2:55 PM set below,
// so the seam stands in for a real 3–6 PM gap. Only the label strategy differs.

// Without coalescing: four hour pills stack between two songs. This is the noise
// the collapse removes — the reason breakpoint runs coalesce at all.
#Preview("Run · stacked (avoided)") {
    SeamPreviewFeed(newest: SeamFixtures.postGapPlaycut) {
        VStack(spacing: 0) {
            ForEach(Array(SeamFixtures.breakpointRun.reversed())) { breakpoint in
                SeamRow(hourLabel: breakpoint.formattedDate)
                    .padding(.vertical, 8)
            }
        }
    }
}

// Recommended: the run collapses to one chip showing the newest hour. Keeps the
// dual-zone label of every other single-hour chip; the skipped hours aren't lost
// because each song row carries its own exact play time.
#Preview("Run · newest (recommended)") {
    SeamPreviewFeed(newest: SeamFixtures.postGapPlaycut) {
        SeamRow(hourLabel: SeamFixtures.runNewestHourLabel)
            .padding(.vertical, 8)
    }
}

// Alternative: one chip showing the span, so a multi-hour gap reads as a gap.
// More honest about dead air / talk blocks, but the range forces station-time-
// only (no dual zone) — judge whether the gap-signal is worth that.
#Preview("Run · range") {
    SeamPreviewFeed(newest: SeamFixtures.postGapPlaycut) {
        SeamRow(hourLabel: SeamFixtures.runRangeLabel)
            .padding(.vertical, 8)
    }
}
