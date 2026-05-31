//
//  AnalyticsBootstrap.swift
//  Analytics
//
//  Entry-point API that hides the PostHog SDK behind the Analytics wrapper.
//  App targets should call `AnalyticsBootstrap.start(...)` at launch instead of touching
//  `PostHogSDK.shared` directly.
//
//  Created by Jake Bromberg on 05/31/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PostHog

/// Namespace for analytics bootstrap APIs. Apps interact with the analytics vendor only through this surface.
///
/// Named `AnalyticsBootstrap` rather than `Analytics` to avoid shadowing the module name at use sites
/// (e.g., `Analytics.ErrorEvent` would otherwise resolve to this enum instead of the module).
public enum AnalyticsBootstrap {
    /// Initializes the analytics SDK. Call exactly once at app launch, before any event capture.
    ///
    /// - Parameters:
    ///   - apiKey: PostHog project API key.
    ///   - host: PostHog instance host URL.
    ///   - buildConfiguration: A short label ("Debug", "TestFlight", "Release") registered as a super-property on every event.
    public static func start(apiKey: String, host: String, buildConfiguration: String) {
        let config = PostHogConfig(apiKey: apiKey, host: host)
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["Build Configuration": buildConfiguration])
    }

    /// Flushes any buffered events. Used on watchOS where the process may be killed quickly after launch.
    public static func flush() {
        PostHogSDK.shared.flush()
    }
}
