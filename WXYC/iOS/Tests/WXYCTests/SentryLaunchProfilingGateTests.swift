//
//  SentryLaunchProfilingGateTests.swift
//  WXYC
//
//  Pins the two policies `setUpSentry()` uses to arm app-launch profiling for
//  WXYC/wxyc-ios-64#949: which environment gets it, and what trace sample rate
//  its sampling decision runs at. The rationale for each lives on the member
//  it pins, in `WXYCApp.swift`.
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

    /// Both rows are load-bearing. The first is the exemption. The second
    /// spells 0.05 rather than reading ``WXYCApp/baseTracesSampleRate``, which
    /// would be a tautology — as written, widening the exemption into "trace
    /// everything on TestFlight" fails here instead of silently multiplying
    /// every other telemetry series by twenty.
    @Test(
        "Only the next launch's profile decision escapes the base trace rate",
        arguments: [
            (true, 1.0),
            (false, 0.05),
        ]
    )
    func exemptsOnlyTheLaunchProfileDecision(forNextAppLaunch: Bool, expected: Double) {
        #expect(WXYCApp.tracesSampleRate(forNextAppLaunch: forNextAppLaunch) == expected)
    }
}
