//
//  SentryLaunchProfilingGateTests.swift
//  WXYC
//
//  Pins the policies `setUpSentry()` uses to arm app-launch profiling for
//  WXYC/wxyc-ios-64#949: which environment gets it, how long it lasts, how many
//  launches it may spend, and what trace sample rate its sampling decision runs
//  at. The rationale for each lives on the member it pins, in `AppBootstrap.swift`.
//
//  Created by Jake Bromberg on 08/18/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Caching
import Core
import Foundation
import Testing
@testable import WXYC

/// A `now` every test that isn't about expiry can pass without thinking.
///
/// File scope and `nonisolated` because this target builds with
/// `-default-isolation=MainActor`, so a `static let` on the suite is
/// main-actor-isolated while `@Test(arguments:)` evaluates its arguments off
/// the main actor.
private nonisolated let withinWindow = AppBootstrap.launchProfilingExpiry.addingTimeInterval(-1)

@Suite("Sentry app-launch profiling gate")
struct SentryLaunchProfilingGateTests {

    // MARK: - Environment

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
        #expect(
            AppBootstrap.shouldProfileAppLaunch(
                environment: environment,
                armedLaunches: 0,
                now: withinWindow
            ) == expected
        )
    }

    // MARK: - Budget

    /// The boundary is the whole point: `budget - 1` still arms, `budget` does
    /// not. A `<=` here would quietly buy one extra profiled launch per install.
    @Test(
        "The budget is exclusive at its own value",
        arguments: [
            (0, true),
            (AppBootstrap.launchProfileBudget - 1, true),
            (AppBootstrap.launchProfileBudget, false),
            (AppBootstrap.launchProfileBudget + 1, false),
        ]
    )
    func stopsAtTheBudget(armedLaunches: Int, expected: Bool) {
        #expect(
            AppBootstrap.shouldProfileAppLaunch(
                environment: .testflight,
                armedLaunches: armedLaunches,
                now: withinWindow
            ) == expected
        )
    }

    // MARK: - Expiry

    @Test(
        "Profiling stops at the expiry instant, not after it",
        arguments: [
            (AppBootstrap.launchProfilingExpiry.addingTimeInterval(-1), true),
            (AppBootstrap.launchProfilingExpiry, false),
            (AppBootstrap.launchProfilingExpiry.addingTimeInterval(1), false),
        ]
    )
    func expires(now: Date, expected: Bool) {
        #expect(
            AppBootstrap.shouldProfileAppLaunch(
                environment: .testflight,
                armedLaunches: 0,
                now: now
            ) == expected
        )
    }

    /// ``WXYCApp/launchProfilingExpiry`` is spelled as an epoch to keep date
    /// parsing off the launch path, which makes its doc comment the only thing
    /// saying which day it is. Derived here from calendar components so a typo
    /// in either one fails rather than sitting there being believed.
    @Test("The expiry epoch is the 2026-09-30T00:00:00Z the comment claims")
    func expiryMatchesItsDocumentedDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let documented = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))
        )

        #expect(AppBootstrap.launchProfilingExpiry == documented)
    }

    // MARK: - Spending the budget

    /// The regression this whole shape exists to prevent. Sentry rewrites the
    /// launch-profile config file at the end of every `SentrySDK.start`, so a
    /// gate that never runs out profiles every launch of every install
    /// indefinitely. Running past the budget proves it does run out, and stays
    /// out.
    @Test("An install arms exactly the budget, then never again")
    func budgetTerminates() {
        let defaults = InMemoryDefaults()

        let armed = (0..<(AppBootstrap.launchProfileBudget + 10)).map { _ in
            AppBootstrap.consumeLaunchProfileBudget(
                defaults: defaults,
                environment: .testflight,
                now: withinWindow
            )
        }

        #expect(armed.prefix(AppBootstrap.launchProfileBudget).allSatisfy { $0 })
        #expect(armed.dropFirst(AppBootstrap.launchProfileBudget).allSatisfy { !$0 })
        #expect(
            defaults.integer(forKey: AppBootstrap.armedLaunchesDefaultsKey)
                == AppBootstrap.launchProfileBudget
        )
    }

    /// A launch that does not arm must not spend, or an App Store install would
    /// walk its own counter to the budget and the TestFlight measurement would
    /// depend on which build the tester happened to run first.
    @Test(
        "A launch the gate refuses spends nothing",
        arguments: [
            (BuildEnvironment.production, withinWindow),
            (BuildEnvironment.testflight, AppBootstrap.launchProfilingExpiry),
        ]
    )
    func refusedLaunchSpendsNothing(environment: BuildEnvironment, now: Date) {
        let defaults = InMemoryDefaults()

        let armed = AppBootstrap.consumeLaunchProfileBudget(
            defaults: defaults,
            environment: environment,
            now: now
        )

        #expect(armed == false)
        #expect(defaults.object(forKey: AppBootstrap.armedLaunchesDefaultsKey) == nil)
    }

    // MARK: - Trace sampling

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
        #expect(AppBootstrap.tracesSampleRate(forNextAppLaunch: forNextAppLaunch) == expected)
    }
}
