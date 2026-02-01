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
@AnalyticsEvent
public struct HandleINIntent {
    public static let name = "Handle INIntent"

    public let context: String
    public let intentData: String

    public init(intentData: String) {
        self.context = "Intents"
        self.intentData = intentData
    }
}

/// Event fired when donating a Siri intent.
@AnalyticsEvent
public struct SiriIntentDonated {
    public static let name = "Intents"

    public let context: String
    public let intentData: String

    public init(intentData: String) {
        self.context = "donateSiriIntent"
        self.intentData = intentData
    }
}

/// Event fired when PauseWXYC intent is executed.
@AnalyticsEvent
public struct PauseWXYCIntent {
    public static let name = "PauseWXYC intent"

    public init() {}
}

/// Event fired when WhatsPlayingOnWXYC intent is executed.
@AnalyticsEvent
public struct WhatsPlayingOnWXYCIntent {
    public static let name = "WhatsPlayingOnWXYC intent"

    public init() {}
}
