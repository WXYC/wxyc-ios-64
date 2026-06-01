//
//  StructuredPostHogAnalytics.swift
//  Analytics
//
//  PostHog implementation of AnalyticsService using structured AnalyticsEvent types.
//
//  Created by Antigravity on 01/14/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import PostHog

/// Production seam wrapping PostHog's capture API so the build_type stamping path
/// is unit-testable. The only production implementation forwards to PostHogSDK.shared.
protocol PostHogClientProtocol {
    func capture(_ name: String, properties: [String: Any]?)
}

private struct PostHogSDKClient: PostHogClientProtocol {
    func capture(_ name: String, properties: [String: Any]?) {
        PostHogSDK.shared.capture(name, properties: properties)
    }
}

/// A concrete implementation of AnalyticsService that reports to PostHog.
///
/// Stamps `build_type` (sourced from the `WXYC_BUILD_TYPE` Info.plist key) onto every
/// captured event's properties. Typed event properties win on collision — if an event's
/// `properties` dict already contains `"build_type"`, that value is preserved.
public final class StructuredPostHogAnalytics: AnalyticsService, @unchecked Sendable {
    public static let shared = StructuredPostHogAnalytics()

    private let client: PostHogClientProtocol
    private let buildType: String

    private convenience init() {
        let buildType = (Bundle.main.infoDictionary?["WXYC_BUILD_TYPE"] as? String) ?? "unknown"
        self.init(client: PostHogSDKClient(), buildType: buildType)
    }

    internal init(client: PostHogClientProtocol, buildType: String) {
        self.client = client
        self.buildType = buildType
    }

    public func capture<T: AnalyticsEvent>(_ event: T) {
        var properties = event.properties ?? [:]
        if properties["build_type"] == nil {
            properties["build_type"] = buildType
        }
        client.capture(T.name, properties: properties)
    }
}
