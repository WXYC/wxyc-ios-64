//
//  EventNameStabilityTests.swift
//  Analytics
//
//  Parameterized tests asserting every event's name matches the expected value.
//  Prevents accidental renames that would break PostHog reporting.
//
//  Created by Jake Bromberg on 02/26/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

private let expectedEventNames: [(String, String)] = [
    // App lifecycle
    (AppLaunch.name, "app_launch"),
    (AppLaunchSimple.name, "app_launch"),
    (AppEnteredBackground.name, "app_entered_background"),
    (BackgroundRefreshCompleted.name, "background_refresh_completed"),
    (ArtworkCacheCleared.name, "artwork_cache_cleared"),
    // Intents
    (HandleINIntent.name, "handle_in_intent"),
    (SiriIntentDonated.name, "siri_intent_donated"),
    (PauseWXYCIntent.name, "pause_wxyc_intent"),
    (WhatsPlayingOnWXYCIntent.name, "whats_playing_on_wxyc_intent"),
    // UI events
    (PartyHornPresented.name, "party_horn_presented"),
    (FeedbackEmailPresented.name, "feedback_email_presented"),
    (FeedbackEmailSent.name, "feedback_email_sent"),
    (PlaycutDetailViewPresented.name, "playcut_detail_view_presented"),
    (StreamingLinkTapped.name, "streaming_link_tapped"),
    (ExternalLinkTapped.name, "external_link_tapped"),
    (CarPlayConnected.name, "carplay_connected"),
    (WidgetGetSnapshot.name, "widget_get_snapshot"),
    (WidgetGetTimeline.name, "widget_get_timeline"),
    // Error
    (ErrorEvent.name, "error"),
]

@Suite("Event Name Stability")
struct EventNameStabilityTests {

    @Test("Event names are stable", arguments: expectedEventNames)
    func eventNameIsStable(actual: String, expected: String) {
        #expect(actual == expected)
    }
}
