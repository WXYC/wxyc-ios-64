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
#if os(watchOS)
import WatchKit
#endif

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

        #if os(watchOS)
        PostHogSDK.shared.register(
            watchOSOSSuperProperties(systemVersion: WKInterfaceDevice.current().systemVersion)
        )
        #endif
    }

    /// Asks the analytics SDK to send any buffered events. Fire-and-forget: the actual network
    /// delivery happens on a background queue, so callers cannot rely on events being on the wire
    /// by the time this returns.
    public static func flush() {
        PostHogSDK.shared.flush()
    }

    /// The `$os`/`$os_name`/`$os_version` super-properties to register on watchOS (#670).
    ///
    /// The vendored PostHog SDK (v3.59.2) only populates these keys inside
    /// `PostHogContext.theStaticContext`'s `#if os(iOS) || os(tvOS) || os(visionOS)` and
    /// `#elseif os(macOS)` branches — there is no `#elseif os(watchOS)` branch. Every event sent
    /// from the watch app therefore resolves to `$os = None` in PostHog even though the events
    /// themselves arrive correctly (verified: 93 play/pause events over 180 days, all carrying
    /// Apple-Watch `$device_model` values). The events are mislabeled, not missing.
    ///
    /// All three keys are registered, not just `$os_name`, because different PostHog insights and
    /// dashboards break down on different ones of the three; registering all three guarantees the
    /// watch shows up regardless of which key a given insight uses. Super-properties registered via
    /// `PostHogSDK.register` take precedence over the SDK's static context on key conflict, but
    /// there is no conflict here — the static context never sets these keys on watchOS.
    ///
    /// Deliberately free of `#if os(watchOS)` and platform APIs so it is unit-testable from any
    /// host; the platform gate lives at the call site in `start(apiKey:host:)`, which is the only
    /// place that needs `WKInterfaceDevice`.
    ///
    /// - Parameter systemVersion: The watch's system version, e.g. `WKInterfaceDevice.current().systemVersion`.
    /// - Returns: The `$os`, `$os_name`, and `$os_version` super-properties to register.
    static func watchOSOSSuperProperties(systemVersion: String) -> [String: String] {
        ["$os": "watchOS", "$os_name": "watchOS", "$os_version": systemVersion]
    }
}
