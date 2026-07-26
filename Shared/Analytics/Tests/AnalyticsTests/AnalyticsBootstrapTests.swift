//
//  AnalyticsBootstrapTests.swift
//  Analytics
//
//  Compile-time guard for the AnalyticsBootstrap.start signature.
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

    @Test("watchOSOSSuperProperties registers all three OS keys")
    func watchOSOSSuperPropertiesRegistersAllThreeOSKeys() {
        // The vendored PostHog SDK has no watchOS branch in its static context, so watchOS
        // events would otherwise resolve to $os = None (#670). This is the pure, platform-agnostic
        // half of the fix, kept testable on any host — see AnalyticsBootstrap.start for the thin
        // #if os(watchOS) call site that feeds this into PostHogSDK.shared.register.
        let properties = AnalyticsBootstrap.watchOSOSSuperProperties(systemVersion: "11.0")

        #expect(properties == ["$os": "watchOS", "$os_name": "watchOS", "$os_version": "11.0"])
    }
}
