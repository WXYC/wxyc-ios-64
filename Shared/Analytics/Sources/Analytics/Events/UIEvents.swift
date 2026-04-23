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

// MARK: - WXYC Recommends

/// Event fired when a recommended artist is tapped in the WXYC Recommends section.
@AnalyticsEvent
public struct RecommendedArtistTapped {
    public let sourceArtist: String
    public let recommendedArtist: String

    public init(sourceArtist: String, recommendedArtist: String) {
        self.sourceArtist = sourceArtist
        self.recommendedArtist = recommendedArtist
    }
}

/// Event fired when an artist detail view is presented from WXYC Recommends.
@AnalyticsEvent
public struct ArtistDetailViewPresented {
    public let artist: String

    public init(artist: String) {
        self.artist = artist
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
