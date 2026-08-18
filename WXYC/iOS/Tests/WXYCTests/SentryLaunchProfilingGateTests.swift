//
//  SentryLaunchProfilingGateTests.swift
//  WXYC
//
//  Pins the policy `setUpSentry()` uses to decide whether app-launch
//  profiling gets armed: TestFlight only. WXYC/wxyc-ios-64#949's "measure
//  first" acceptance criterion needs one real cold-launch profile from a
//  TestFlight build, and every other environment — `production` above all —
//  stays off, so the memory cost of continuous stack sampling never reaches
//  App Store-scale traffic.
//
//  Created by Jake Bromberg on 08/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Testing
@testable import WXYC

@Suite("Sentry app-launch profiling gate")
struct SentryLaunchProfilingGateTests {

    @Test(
        "Profiling is armed for TestFlight and only TestFlight",
        arguments: [
            (BuildEnvironment.testflight, true),
            (BuildEnvironment.production, false),
            (BuildEnvironment.debug, false),
            (BuildEnvironment.simulator, false),
            (BuildEnvironment.adhoc, false),
        ]
    )
    func armsOnlyForTestFlight(environment: BuildEnvironment, expected: Bool) {
        #expect(WXYCApp.shouldProfileAppLaunch(for: environment) == expected)
    }
}
