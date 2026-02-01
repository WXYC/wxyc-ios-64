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
    public static let name = "party horn presented"

    public init() {}
}

// MARK: - Feedback Email

/// Event fired when the feedback email composer is presented.
@AnalyticsEvent
public struct FeedbackEmailPresented {
    public static let name = "feedback email presented"

    public init() {}
}

/// Event fired when a feedback email is sent successfully.
@AnalyticsEvent
public struct FeedbackEmailSent {
    public static let name = "feedback email sent"

    public init() {}
}

// MARK: - Playcut Detail

/// Event fired when a playcut detail view is presented.
@AnalyticsEvent
public struct PlaycutDetailViewPresented {
    public static let name = "playcut detail view presented"

    public let artist: String
    public let album: String

    public init(artist: String, album: String) {
        self.artist = artist
        self.album = album
    }
}

/// Event fired when a streaming service link is tapped.
@AnalyticsEvent
public struct StreamingLinkTapped {
    public static let name = "streaming link tapped"

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
    public static let name = "external link tapped"

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
@AnalyticsEvent
public struct CarPlayConnected {
    public static let name = "carplay connected"

    public init() {}
}

// MARK: - Widget

/// Event fired when the widget requests a snapshot.
@AnalyticsEvent
public struct WidgetGetSnapshot {
    public static let name = "getSnapshot"

    public let context: String
    public let family: String

    public init(family: String) {
        self.context = "NowPlayingWidget"
        self.family = family
    }
}

/// Event fired when the widget requests a timeline.
@AnalyticsEvent
public struct WidgetGetTimeline {
    public static let name = "getTimeline"

    public let context: String
    public let family: String

    public init(family: String) {
        self.context = "NowPlayingWidget"
        self.family = family
    }
}
