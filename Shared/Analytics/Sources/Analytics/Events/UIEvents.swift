//
//  UIEvents.swift
//  Analytics
//
//  Structured analytics events for UI interactions.
//
//  Created by Claude on 01/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - Party Horn

/// Event fired when the party horn easter egg is presented.
@AnalyticsEvent
public struct PartyHornPresented {
    public init() {}
}

// MARK: - Feedback Email

/// Event fired when the feedback email composer is presented.
@AnalyticsEvent
public struct FeedbackEmailPresented {
    public init() {}
}

/// Event fired when a feedback email is sent successfully.
@AnalyticsEvent
public struct FeedbackEmailSent {
    public init() {}
}

// MARK: - Bug Report

/// Event fired when the in-app bug report sheet is presented.
@AnalyticsEvent
public struct BugReportPresented {
    public init() {}
}

/// Event fired when a bug report is submitted to Sentry.
@AnalyticsEvent
public struct BugReportSent {
    public init() {}
}

// MARK: - Request Line

/// Event fired when the Request Line sheet is presented.
///
/// `source` is the entry point: `"banner"` (the on-air banner's say-hi chip)
/// or `"station"` (the Station tab's booth rows).
@AnalyticsEvent
public struct RequestLineOpened {
    public let source: String

    public init(source: String) {
        self.source = source
    }
}

/// Event fired when a song request is sent from the Request Line.
@AnalyticsEvent
public struct RequestLineSongRequested {
    public let source: String

    public init(source: String) {
        self.source = source
    }
}

/// Event fired when the listener taps through to call the request line.
@AnalyticsEvent
public struct RequestLineCallPlaced {
    public let source: String

    public init(source: String) {
        self.source = source
    }
}

// MARK: - Support the Station

/// Event fired when the listener taps through to the donation page.
///
/// The only donation event the app captures. Conversion belongs to the payment
/// platform's own reporting and to LGL, both of which see the actual gift — the
/// app only ever knows about the tap, and `capture()` is a billing decision
/// against a shared org quota.
@AnalyticsEvent
public struct DonateTapped {
    public let source: String

    public init(source: String) {
        self.source = source
    }
}

// MARK: - Playcut Detail

/// Event fired when a playcut detail view is presented.
@AnalyticsEvent
public struct PlaycutDetailViewPresented {
    public let songTitle: String
    public let artist: String
    public let album: String

    public init(songTitle: String, artist: String, album: String) {
        self.songTitle = songTitle
        self.artist = artist
        self.album = album
    }
}

/// Event fired when a streaming service link is tapped.
@AnalyticsEvent
public struct StreamingLinkTapped {
    public let service: String
    public let songTitle: String
    public let artist: String
    public let album: String

    public init(service: String, songTitle: String, artist: String, album: String) {
        self.service = service
        self.songTitle = songTitle
        self.artist = artist
        self.album = album
    }
}

/// Event fired when an external link (Discogs, Wikipedia) is tapped.
@AnalyticsEvent
public struct ExternalLinkTapped {
    public let service: String
    public let songTitle: String
    public let artist: String
    public let album: String

    public init(service: String, songTitle: String, artist: String, album: String) {
        self.service = service
        self.songTitle = songTitle
        self.artist = artist
        self.album = album
    }
}

// MARK: - CarPlay

/// Event fired when CarPlay connects.
///
/// Overrides the auto-derived name (`car_play_connected`) to use `carplay_connected`.
@AnalyticsEvent
public struct CarPlayConnected {
    public static let name = "carplay_connected"

    public init() {}
}

// MARK: - Widget

/// Event fired when the widget requests a snapshot.
@AnalyticsEvent
public struct WidgetGetSnapshot {
    public let family: String

    public init(family: String) {
        self.family = family
    }
}

/// How a single WidgetKit timeline refresh actually turned out.
///
/// The cases are the terminal shapes the widget's timeline provider can
/// genuinely produce, not a wish-list: it either builds an entry from a
/// now-playing item, or it ships its empty state because no such item was
/// available. The empty case is split by whether the playlist fetch behind it
/// reported an error, because those two look identical on screen and want
/// different responses — see `PlaylistService.fetchErrorCount()`, whose whole
/// reason for existing is that "a sustained failure looks like a quiet night".
public enum WidgetTimelineOutcome: String, CaseIterable, Sendable {
    /// An entry was produced. The overwhelming majority of refreshes, and the
    /// case ``WidgetGetTimeline`` deliberately refuses to represent.
    case ok

    /// No now-playing item was available and no fetch error was recorded, so
    /// the empty-state entry shipped. Either the station genuinely has nothing
    /// on the flowsheet, or the cache handed back an empty playlist.
    case empty

    /// As ``empty``, and the playlist fetch this refresh performed reported an
    /// error. Strictly a refinement of ``empty``: a failed fetch collapses to
    /// an empty playlist upstream, so it can never coexist with a rendered
    /// entry.
    case fetchFailed = "fetch_failed"

    /// Whether this outcome is worth a PostHog row.
    ///
    /// The gate for ``WidgetGetTimeline``. Adding a case forces a decision here
    /// rather than silently inheriting the old capture-everything behavior.
    var isReportable: Bool {
        switch self {
        case .ok: false
        case .empty, .fetchFailed: true
        }
    }
}

/// Event fired when a widget timeline refresh ends in an outcome worth
/// recording — **not** on every refresh.
///
/// ## Why this event is outcome-gated
///
/// WidgetKit, not the listener, decides how often a timeline is requested, so
/// an unconditional capture here is a per-timer emission that scales with
/// installed-widget count rather than with engagement. It was doing exactly
/// that: 21,160 rows over twelve days across 113 people — 187 each — for a
/// diagnostic with, verified against PostHog project `134292` on 2026-09-12,
/// **zero** saved-insight and **zero** alert consumers under either this name
/// or its 3.1-era predecessor `getTimeline` (WXYC/wxyc-ios-64#1065, #1062).
///
/// With no consumer of the healthy rows there is no denominator to preserve,
/// so ``WidgetTimelineOutcome/ok`` is dropped outright rather than sampled: the
/// failable initializer below returns `nil` for it, and there is no other way
/// to build the event. The alternative considered — a stable 1-in-10 sample
/// keyed on the install id, with the rate carried as a property — costs ~10% of
/// the volume forever to keep a ratio nobody reads. Reach for it only if a
/// consumer of the healthy path appears; the trade is then a real one.
///
/// The consequence to know before writing a query: **this event no longer has a
/// denominator.** `count(widget_get_timeline)` is a count of *problem*
/// refreshes, not of refreshes. A rate needs a denominator from elsewhere —
/// `widget_get_snapshot`, or a restored healthy sample.
///
/// The name is unchanged on purpose (WXYC/wxyc-ios-64#845): renaming would cost
/// taxonomy continuity without removing a single row. `EventNameStabilityTests`
/// pins it.
@AnalyticsEvent
public struct WidgetGetTimeline {
    public let family: String
    public let outcome: String

    /// Builds the event for `outcome`, or returns `nil` when the refresh went
    /// fine and is therefore not worth a row.
    ///
    /// Failable rather than an `if` at the capture site, so the gate lives in this
    /// package — where it is host-testable — instead of in the widget
    /// extension, which only `xcodebuild` compiles. It is also the reason no
    /// unconditional initializer exists: an unfiltered capture is not
    /// expressible.
    ///
    /// `outcome` is stored as its `rawValue` because `@AnalyticsEvent` copies
    /// stored properties into `properties` verbatim, without reaching for
    /// `.rawValue` on an enum (same reason as `FetchPlaylistEvent` in the
    /// Playlist package and `RequestLineAuthFailedEvent` in MusicShareKit).
    public init?(family: String, outcome: WidgetTimelineOutcome) {
        guard outcome.isReportable else { return nil }
        self.family = family
        self.outcome = outcome.rawValue
    }
}
