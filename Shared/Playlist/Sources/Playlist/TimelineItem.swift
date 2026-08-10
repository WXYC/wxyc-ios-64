//
//  TimelineItem.swift
//  Playlist
//
//  Render-ready timeline items and the coalescing pass that produces them:
//  each maximal run of adjacent talksets and breakpoints collapses into a single
//  seam, so the feed shows at most one break between any two songs.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

/// A render-ready item in the playlist timeline, produced by
/// ``Playlist/timelineItems``. Each maximal run of adjacent talksets and
/// breakpoints is collapsed into a single ``Seam``; playcuts and show markers
/// pass through unchanged.
public enum TimelineItem: Identifiable, Sendable {
    case playcut(Playcut)
    case seam(Seam)
    case showMarker(ShowMarker)

    public var id: UInt64 {
        switch self {
        case .playcut(let playcut): playcut.id
        case .seam(let seam): seam.id
        case .showMarker(let marker): marker.id
        }
    }
}

/// A single break between songs: the DJ got on the mic, an hour boundary passed,
/// or both. A run of several such markers with no song between them coalesces
/// into one seam, so the feed shows at most one between any two songs.
public struct Seam: Identifiable, Sendable, Equatable {
    /// Stable identity — the id of the run's newest entry. New logs land at the
    /// top of the feed, not inside an older gap, so an untouched gap keeps its
    /// id across refreshes.
    ///
    /// A dj-site reorder is the one thing that can change a settled gap's
    /// membership: ordering now follows `(show_id, play_order)` rather than the
    /// row id (#839), so a DJ dragging a talkset can move it into or out of an
    /// older run. When that lands on the run's *newest* member the seam's id
    /// changes, which SwiftUI reads as a delete plus an insert rather than a
    /// move — the reordered seam cross-fades instead of sliding. That is the
    /// accepted cost of showing the reorder at all; the alternative (an id
    /// derived from the run's contents) churns on every enrichment instead.
    public let id: UInt64

    /// Whether the run contained a talkset (the DJ spoke). Drives the mic glyph
    /// and the "mic break" label.
    public let hasMicBreak: Bool

    /// The newest breakpoint in the run, whose ``Breakpoint/hourLabel()`` gives
    /// the hour to show. `nil` when the run crossed no hour boundary (a lone
    /// talkset). For a multi-hour run this is the newest hour — the one the feed
    /// resumes into.
    public let breakpoint: Breakpoint?

    public init(id: UInt64, hasMicBreak: Bool, breakpoint: Breakpoint?) {
        self.id = id
        self.hasMicBreak = hasMicBreak
        self.breakpoint = breakpoint
    }

    /// A plain-text label for surfaces without the styled chip — watchOS, CarPlay,
    /// and VoiceOver: "Mic break", "3PM ET", or "Mic break, 3PM ET". The comma
    /// (not the chip's middot) reads cleanly aloud.
    public var plainLabel: String {
        let hour = breakpoint?.formattedDate
        return switch (hasMicBreak, hour) {
        case (true, let hour?): "Mic break, \(hour)"
        case (true, nil): "Mic break"
        case (false, let hour?): hour
        case (false, nil): ""
        }
    }
}

public extension Playlist {
    /// ``timelineEntries`` folded into render-ready ``TimelineItem`` values, with
    /// each maximal run of adjacent talksets and breakpoints collapsed into one
    /// ``Seam``. Playcuts and show markers pass through and break a run, so there
    /// is at most one seam between any two songs (or between a song and a show
    /// boundary). Ordering matches ``timelineEntries`` — newest first.
    var timelineItems: [TimelineItem] {
        var items: [TimelineItem] = []
        var run: [any PlaylistEntry] = []

        func flushRun() {
            guard let newest = run.first else { return }
            let hasMicBreak = run.contains { $0 is Talkset }
            // `timelineEntries` is newest-first, so the first breakpoint in the
            // run is the newest — the hour the feed resumes into.
            let newestBreakpoint = run.lazy.compactMap { $0 as? Breakpoint }.first
            items.append(.seam(Seam(id: newest.id, hasMicBreak: hasMicBreak, breakpoint: newestBreakpoint)))
            run.removeAll(keepingCapacity: true)
        }

        for entry in timelineEntries {
            switch entry {
            case is Talkset, is Breakpoint:
                run.append(entry)
            case let playcut as Playcut:
                flushRun()
                items.append(.playcut(playcut))
            case let marker as ShowMarker:
                flushRun()
                items.append(.showMarker(marker))
            default:
                flushRun()
            }
        }
        flushRun()

        return items
    }
}
