//
//  AnalyticsBootstrapTests.swift
//  Analytics
//
//  Compile-time guard for the AnalyticsBootstrap.start signature, and the watchOS platform
//  labels the bootstrap stamps onto every event.
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics

@Suite("AnalyticsBootstrap")
struct AnalyticsBootstrapTests {

    @Test("start() compiles without buildConfiguration parameter")
    func startSignatureHasNoBuildConfigurationParameter() {
        // Compile-time guard: if the buildConfiguration parameter is reintroduced,
        // this call fails to compile. The integration behavior (super-prop is registered
        // with the Info.plist value) is verified by the post-merge manual smoke test.
        let _: (String, String) -> Void = { apiKey, host in
            AnalyticsBootstrap.start(apiKey: apiKey, host: host)
        }
    }

    @Test("watchOSPlatformProperties labels the OS and the device type")
    func watchOSPlatformPropertiesLabelsOSAndDeviceType() {
        // The vendored PostHog SDK has no watchOS branch in its static context, so watchOS
        // events would otherwise resolve to $os = None (#670) and $device_type = None. This is
        // the pure, platform-agnostic half of the fix, kept testable on any host — see
        // AnalyticsBootstrap.start for the thin #if os(watchOS) call site that feeds it into the
        // before-send hook.
        // Use a sentinel that can never be a real OS version, so this also proves the
        // systemVersion argument is threaded through to $os_version rather than hardcoded.
        let properties = AnalyticsBootstrap.watchOSPlatformProperties(systemVersion: "sentinel-99.9")

        #expect(properties == [
            "$os": "watchOS",
            "$os_name": "watchOS",
            "$os_version": "sentinel-99.9",
            "$device_type": "Wearable",
        ])
    }

    @Test("stamping platform properties onto an event", arguments: platformStampingCases)
    func stampingPlatformProperties(_ testCase: PlatformStampingCase) {
        let stamped = AnalyticsBootstrap.stamping(testCase.platformProperties, onto: testCase.eventProperties)

        #expect(stamped as? [String: String] == testCase.expected)
    }
}

/// One row of the platform-stamping table: what an event carries on its way into the before-send
/// hook, and what it must carry on the way out.
struct PlatformStampingCase: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let platformProperties: [String: String]
    let eventProperties: [String: String]
    let expected: [String: String]
}

nonisolated let platformStampingCases: [PlatformStampingCase] = [
    // `Application Installed` and the first `Application Opened` are captured inside
    // `PostHogSDK.setup`, before anything registered after it can apply. They are the events that
    // still reached PostHog unlabeled from 3.2.x watch builds.
    PlatformStampingCase(
        testDescription: "labels an event that carries no platform keys",
        platformProperties: ["$os_name": "watchOS", "$device_type": "Wearable"],
        eventProperties: ["$app_version": "3.2.2"],
        expected: ["$app_version": "3.2.2", "$os_name": "watchOS", "$device_type": "Wearable"]
    ),
    // 3.2.x registered `$os_version` as a persisted super-property. Left to win, that stored value
    // would pin every later event to the watchOS version the build first launched on.
    PlatformStampingCase(
        testDescription: "replaces a stale value persisted by an earlier build",
        platformProperties: ["$os_version": "27.0"],
        eventProperties: ["$os_version": "26.5"],
        expected: ["$os_version": "27.0"]
    ),
    PlatformStampingCase(
        testDescription: "leaves the event's own properties alone",
        platformProperties: ["$os_name": "watchOS"],
        eventProperties: ["reason": "Watch play/pause tapped", "source": "watch"],
        expected: ["reason": "Watch play/pause tapped", "source": "watch", "$os_name": "watchOS"]
    ),
]
