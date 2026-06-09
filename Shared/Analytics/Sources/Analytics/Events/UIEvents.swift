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

// MARK: - Playcut Detail

/// Event fired when a playcut detail view is presented.
@AnalyticsEvent
public struct PlaycutDetailViewPresented {
    public let artist: String
    public let album: String

    public init(artist: String, album: String) {
        self.artist = artist
        self.album = album
    }
}

/// Event fired when PlaycutDetailView resolves metadata, dimensioned by source.
///
/// `source` is `"inline"` when the v2 flowsheet row's inline fields were
/// authoritative (no `/proxy/metadata/album` call), `"fallback"` when the
/// service issued a proxy fetch.
///
/// `metadataStatus` is the row's wire enum value (`"enriched_match"`,
/// `"enriching"`, etc.) or `"absent"` for V1 rows / pre-Epic-C deploys.
///
/// Lets us measure whether `WXYC/wxyc-ios-64#270` actually shifted the
/// hot path off the proxy without conflating with the fallback path.
@AnalyticsEvent
public struct PlaycutMetadataResolved {
    public let source: String
    public let metadataStatus: String

    public init(source: String, metadataStatus: String) {
        self.source = source
        self.metadataStatus = metadataStatus
    }
}

/// Event fired when a streaming service link is tapped.
@AnalyticsEvent
public struct StreamingLinkTapped {
    public let service: String
    public let artist: String
    public let album: String

    public init(service: String, artist: String, album: String) {
        self.service = service
        self.artist = artist
        self.album = album
    }
}

/// Event fired when an external link (Discogs, Wikipedia) is tapped.
@AnalyticsEvent
public struct ExternalLinkTapped {
    public let service: String
    public let artist: String
    public let album: String

    public init(service: String, artist: String, album: String) {
        self.service = service
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
@AnalyticsEvent
public struct WidgetGetTimeline {
    public let family: String

    public init(family: String) {
        self.family = family
    }
}
