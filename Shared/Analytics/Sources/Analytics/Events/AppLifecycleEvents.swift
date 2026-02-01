//
//  AppLifecycleEvents.swift
//  Analytics
//
//  Structured analytics events for app lifecycle (launch, background, foreground).
//
//  Created by Claude on 01/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation

// MARK: - App Launch

/// Event fired when the app launches.
@AnalyticsEvent
public struct AppLaunch {
    public static let name = "app launch"

    public let hasUsedThemePicker: Bool
    public let buildType: String

    public init(hasUsedThemePicker: Bool, buildType: String) {
        self.hasUsedThemePicker = hasUsedThemePicker
        self.buildType = buildType
    }
}

/// Simplified app launch event for watchOS and tvOS.
@AnalyticsEvent
public struct AppLaunchSimple {
    public static let name = "app launch"

    public init() {}
}

// MARK: - Background Events

/// Event fired when the app enters the background.
@AnalyticsEvent
public struct AppEnteredBackground {
    public static let name = "App entered background"

    public let isPlaying: Bool

    public init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }
}

/// Event fired when background refresh completes.
@AnalyticsEvent
public struct BackgroundRefreshCompleted {
    public static let name = "Background refresh completed"

    public let entryCount: String

    public init(entryCount: Int) {
        self.entryCount = "\(entryCount)"
    }
}

// MARK: - Cache Events

/// Event fired when the artwork cache is cleared.
@AnalyticsEvent
public struct ArtworkCacheCleared {
    public static let name = "Artwork cache cleared"

    public let source: String
    public let sizeBytes: Int64

    public init(source: String, sizeBytes: Int64) {
        self.source = source
        self.sizeBytes = sizeBytes
    }
}
