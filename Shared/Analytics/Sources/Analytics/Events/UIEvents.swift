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
public struct PartyHornPresented: AnalyticsEvent {
    public static let name = "party horn presented"

    public var properties: [String: Any]? { nil }

    public init() {}
}

// MARK: - Feedback Email

/// Event fired when the feedback email composer is presented.
public struct FeedbackEmailPresented: AnalyticsEvent {
    public static let name = "feedback email presented"

    public var properties: [String: Any]? { nil }

    public init() {}
}

/// Event fired when a feedback email is sent successfully.
public struct FeedbackEmailSent: AnalyticsEvent {
    public static let name = "feedback email sent"

    public var properties: [String: Any]? { nil }

    public init() {}
}

// MARK: - Playcut Detail

/// Event fired when a playcut detail view is presented.
public struct PlaycutDetailViewPresented: AnalyticsEvent {
    public static let name = "playcut detail view presented"

    public let artist: String
    public let album: String

    public var properties: [String: Any]? {
        [
            "artist": artist,
            "album": album
        ]
    }

    public init(artist: String, album: String) {
        self.artist = artist
        self.album = album
    }
}

/// Event fired when a streaming service link is tapped.
public struct StreamingLinkTapped: AnalyticsEvent {
    public static let name = "streaming link tapped"

    public let service: String
    public let artist: String
    public let album: String

    public var properties: [String: Any]? {
        [
            "service": service,
            "artist": artist,
            "album": album
        ]
    }

    public init(service: String, artist: String, album: String) {
        self.service = service
        self.artist = artist
        self.album = album
    }
}

/// Event fired when an external link (Discogs, Wikipedia) is tapped.
public struct ExternalLinkTapped: AnalyticsEvent {
    public static let name = "external link tapped"

    public let service: String
    public let artist: String
    public let album: String

    public var properties: [String: Any]? {
        [
            "service": service,
            "artist": artist,
            "album": album
        ]
    }

    public init(service: String, artist: String, album: String) {
        self.service = service
        self.artist = artist
        self.album = album
    }
}

// MARK: - CarPlay

/// Event fired when CarPlay connects.
public struct CarPlayConnected: AnalyticsEvent {
    public static let name = "carplay connected"

    public var properties: [String: Any]? { nil }

    public init() {}
}

// MARK: - Widget

/// Event fired when the widget requests a snapshot.
public struct WidgetGetSnapshot: AnalyticsEvent {
    public static let name = "getSnapshot"

    public let family: String

    public var properties: [String: Any]? {
        [
            "context": "NowPlayingWidget",
            "family": family
        ]
    }

    public init(family: String) {
        self.family = family
    }
}

/// Event fired when the widget requests a timeline.
public struct WidgetGetTimeline: AnalyticsEvent {
    public static let name = "getTimeline"

    public let family: String

    public var properties: [String: Any]? {
        [
            "context": "NowPlayingWidget",
            "family": family
        ]
    }

    public init(family: String) {
        self.family = family
    }
}
