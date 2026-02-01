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
public struct AppLaunch: AnalyticsEvent {
    public static let name = "app launch"

    public let hasUsedThemePicker: Bool
    public let buildType: String

    public var properties: [String: Any]? {
        [
            "has_used_theme_picker": hasUsedThemePicker,
            "build_type": buildType
        ]
    }

    public init(hasUsedThemePicker: Bool, buildType: String) {
        self.hasUsedThemePicker = hasUsedThemePicker
        self.buildType = buildType
    }
}

/// Simplified app launch event for watchOS and tvOS.
public struct AppLaunchSimple: AnalyticsEvent {
    public static let name = "app launch"

    public var properties: [String: Any]? { nil }

    public init() {}
}

// MARK: - Background Events

/// Event fired when the app enters the background.
public struct AppEnteredBackground: AnalyticsEvent {
    public static let name = "App entered background"

    public let isPlaying: Bool

    public var properties: [String: Any]? {
        ["Is Playing?": isPlaying]
    }

    public init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }
}

/// Event fired when background refresh completes.
public struct BackgroundRefreshCompleted: AnalyticsEvent {
    public static let name = "Background refresh completed"

    public let entryCount: Int

    public var properties: [String: Any]? {
        ["entry_count": "\(entryCount)"]
    }

    public init(entryCount: Int) {
        self.entryCount = entryCount
    }
}

// MARK: - Cache Events

/// Event fired when the artwork cache is cleared.
public struct ArtworkCacheCleared: AnalyticsEvent {
    public static let name = "Artwork cache cleared"

    public let source: String
    public let sizeBytes: Int64

    public var properties: [String: Any]? {
        [
            "source": source,
            "size_bytes": sizeBytes
        ]
    }

    public init(source: String, sizeBytes: Int64) {
        self.source = source
        self.sizeBytes = sizeBytes
    }
}
