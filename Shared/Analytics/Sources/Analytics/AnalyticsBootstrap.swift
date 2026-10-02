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
    /// On watchOS it also labels every event with the platform, which the SDK does not do there:
    /// see ``watchOSPlatformProperties(systemVersion:)``.
    ///
    /// - Parameters:
    ///   - apiKey: PostHog project API key.
    ///   - host: PostHog instance host URL.
    public static func start(apiKey: String, host: String) {
        let config = PostHogConfig(apiKey: apiKey, host: host)

        #if os(watchOS)
        // Installed on the config, so it is in place before `setup` captures its first event.
        // See `stamping(_:onto:)` for why this is a before-send hook and not a super-property.
        let platformProperties = watchOSPlatformProperties(
            systemVersion: WKInterfaceDevice.current().systemVersion
        )
        config.setBeforeSend { event in
            event.properties = stamping(platformProperties, onto: event.properties)
            return event
        }
        #endif

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

    /// The platform labels every watchOS event carries: `$os`, `$os_name`, `$os_version` (#670)
    /// and `$device_type`.
    ///
    /// The vendored PostHog SDK (checked through v3.71.6, and on its `main`) only populates the OS
    /// keys inside `PostHogContext.theStaticContext`'s `#if os(iOS) || os(tvOS) || os(visionOS)`
    /// and `#elseif os(macOS)` branches, and `PostHogContext.deviceType` returns `nil` outside
    /// iOS, tvOS and macOS — there is no watchOS branch in either. Every event sent from the watch
    /// app therefore resolves to `$os = None` and `$device_type = None` in PostHog even though the
    /// events themselves arrive correctly. The events are mislabeled, not missing.
    ///
    /// All three OS keys are set, not just `$os_name`, because different PostHog insights and
    /// dashboards break down on different ones of the three; setting all three guarantees the
    /// watch shows up regardless of which key a given insight uses. `$device_type` is `Wearable`
    /// because that is PostHog's own name for the class — its web SDK reports
    /// `Desktop`/`Mobile`/`Tablet`/`Console`/`Wearable` — so the watch lands in a bucket PostHog
    /// already knows rather than in one only this app uses.
    ///
    /// Deliberately free of `#if os(watchOS)` and platform APIs so it is unit-testable from any
    /// host; the platform gate lives at the call site in `start(apiKey:host:)`, which is the only
    /// place that needs `WKInterfaceDevice`.
    ///
    /// - Parameter systemVersion: The watch's system version, e.g. `WKInterfaceDevice.current().systemVersion`.
    /// - Returns: The `$os`, `$os_name`, `$os_version` and `$device_type` values to stamp.
    static func watchOSPlatformProperties(systemVersion: String) -> [String: String] {
        [
            "$os": "watchOS",
            "$os_name": "watchOS",
            "$os_version": systemVersion,
            "$device_type": "Wearable",
        ]
    }

    /// Returns `eventProperties` with `platformProperties` laid over it — the pure half of the
    /// before-send hook `start(apiKey:host:)` installs on watchOS.
    ///
    /// The labels were first registered as super-properties, after `setup` returned. That missed
    /// the events `setup` captures itself: `Application Installed` and the first
    /// `Application Opened` still reached PostHog with `$os = None` from 3.2.x watch builds, so a
    /// chart of installs by platform kept undercounting the watch. A before-send hook sees every
    /// event, including those.
    ///
    /// The platform value wins on a key collision. The SDK never sets these keys on watchOS, so
    /// the only thing that can collide is a super-property an earlier build persisted — and its
    /// `$os_version` is the version that build first launched on, which goes stale at the next
    /// watchOS update.
    ///
    /// - Parameters:
    ///   - platformProperties: The labels to stamp; see ``watchOSPlatformProperties(systemVersion:)``.
    ///   - eventProperties: The event's properties as the SDK assembled them.
    /// - Returns: The event's properties, labeled.
    static func stamping(
        _ platformProperties: [String: String],
        onto eventProperties: [String: Any]
    ) -> [String: Any] {
        eventProperties.merging(platformProperties) { _, platformValue in platformValue }
    }
}
