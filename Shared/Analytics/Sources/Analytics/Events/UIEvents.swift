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

/// Event fired when the widget requests a timeline.
///
/// Carries the refresh decision, not just the request: the interval the
/// provider picked is what determines how much of the widget's reload budget
/// the request costs. Summing `refresh_interval_minutes` across a day is how
/// `AppServices.WidgetRefreshSchedule`'s tier table gets validated against
/// real usage rather than the simulated days in its tests.
@AnalyticsEvent
public struct WidgetGetTimeline {
    public let family: String

    /// The `.after` interval the provider scheduled, in whole minutes.
    public let refreshIntervalMinutes: Int

    /// Whether the entry rendered now was already past the staleness
    /// threshold — i.e. the refresh arrived too late to be current.
    public let isStale: Bool

    public init(family: String, refreshIntervalMinutes: Int, isStale: Bool) {
        self.family = family
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.isStale = isStale
    }
}
