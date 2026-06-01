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
    /// The build type is read from the `WXYC_BUILD_TYPE` key on `Bundle.main.infoDictionary`,
    /// which is populated at build time by the `WXYC_BUILD_TYPE` xcconfig variable. The value
    /// is registered as the `"Build Configuration"` super-property on every event for backward
    /// compatibility with existing PostHog insights that filter on that key.
    ///
    /// - Parameters:
    ///   - apiKey: PostHog project API key.
    ///   - host: PostHog instance host URL.
    public static func start(apiKey: String, host: String) {
        let config = PostHogConfig(apiKey: apiKey, host: host)
        PostHogSDK.shared.setup(config)

        let buildType = (Bundle.main.infoDictionary?["WXYC_BUILD_TYPE"] as? String) ?? "unknown"
        PostHogSDK.shared.register(["Build Configuration": buildType])
    }

    /// Asks the analytics SDK to send any buffered events. Fire-and-forget: the actual network
    /// delivery happens on a background queue, so callers cannot rely on events being on the wire
    /// by the time this returns.
    public static func flush() {
        PostHogSDK.shared.flush()
    }
}
