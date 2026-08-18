//
//  SentryLaunchProfilingGateTests.swift
//  WXYC
//
//  Pins the two policies `setUpSentry()` uses to arm app-launch profiling:
//  which environment gets it, and what trace sample rate its sampling
//  decision runs at. WXYC/wxyc-ios-64#949's "measure first" acceptance
//  criterion needs one real cold-launch profile from a TestFlight build, and
//  every other environment — `production` above all — stays off, so the
//  memory cost of continuous stack sampling never reaches App Store-scale
//  traffic.
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

    /// The launch-profile decision is the one transaction that must not be
    /// sampled out, and the only one: at 5% it would arrive about once per 20
    /// TestFlight launches, which over a tester population of a handful is how
    /// #949 ships looking correct and yields nothing.
    ///
    /// Both rows are load-bearing. The first is the exemption. The second pins
    /// the base rate at the 5% every other transaction has always paid, so
    /// widening the exemption into "trace everything on TestFlight" — the
    /// obvious and much blunter alternative — fails here rather than silently
    /// multiplying every other telemetry series by twenty.
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
