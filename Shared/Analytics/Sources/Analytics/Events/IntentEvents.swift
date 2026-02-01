//
//  IntentEvents.swift
//  Analytics
//
//  Structured analytics events for Siri and Shortcuts intents.
//
//  Created by Claude on 01/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - Intent Events

/// Event fired when handling an INPlayMediaIntent from Siri.
public struct HandleINIntent: AnalyticsEvent {
    public static let name = "Handle INIntent"

    public let intentData: String

    public var properties: [String: Any]? {
        [
            "context": "Intents",
            "intent data": intentData
        ]
    }

    public init(intentData: String) {
        self.intentData = intentData
    }
}

/// Event fired when donating a Siri intent.
public struct SiriIntentDonated: AnalyticsEvent {
    public static let name = "Intents"

    public let intentData: String

    public var properties: [String: Any]? {
        [
            "context": "donateSiriIntent",
            "intent data": intentData
        ]
    }

    public init(intentData: String) {
        self.intentData = intentData
    }
}

/// Event fired when PauseWXYC intent is executed.
public struct PauseWXYCIntent: AnalyticsEvent {
    public static let name = "PauseWXYC intent"

    public var properties: [String: Any]? { nil }

    public init() {}
}

/// Event fired when WhatsPlayingOnWXYC intent is executed.
public struct WhatsPlayingOnWXYCIntent: AnalyticsEvent {
    public static let name = "WhatsPlayingOnWXYC intent"

    public var properties: [String: Any]? { nil }

    public init() {}
}
