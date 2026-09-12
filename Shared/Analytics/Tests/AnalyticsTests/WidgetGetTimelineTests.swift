//
//  WidgetGetTimelineTests.swift
//  Analytics
//
//  Tests that the widget timeline event only exists for an outcome worth a row,
//  and that when it does exist it carries the family that asked, so problem
//  refreshes can still be counted per widget size.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("WidgetGetTimeline event")
struct WidgetGetTimelineTests {

    // MARK: - The gate

    @Test("The healthy path produces no event at all")
    func healthyOutcomeIsNotConstructible() {
        #expect(WidgetGetTimeline(family: "systemMedium", outcome: .ok) == nil)
    }

    @Test(
        "Each problem outcome still produces an event",
        arguments: [WidgetTimelineOutcome.empty, .fetchFailed]
    )
    func problemOutcomesAreCaptured(outcome: WidgetTimelineOutcome) throws {
        let event = try #require(WidgetGetTimeline(family: "systemMedium", outcome: outcome))

        let properties = try #require(event.properties)

        #expect(properties["outcome"] as? String == outcome.rawValue)
    }

    @Test("`ok` is the only outcome the gate drops")
    func okIsTheOnlyDroppedOutcome() {
        let dropped = WidgetTimelineOutcome.allCases.filter {
            WidgetGetTimeline(family: "systemMedium", outcome: $0) == nil
        }

        #expect(dropped == [.ok])
    }

    // MARK: - Payload

    @Test("Carries the requesting family")
    func carriesFamily() throws {
        let event = try #require(WidgetGetTimeline(family: "systemMedium", outcome: .empty))

        let properties = try #require(event.properties)

        #expect(properties["family"] as? String == "systemMedium")
    }

    // MARK: - Wire stability

    /// The outcome values go on the wire as a PostHog property, so they are as
    /// breakable as the event name that `EventNameStabilityTests` pins.
    @Test(
        "Outcome wire values are stable",
        arguments: [
            (WidgetTimelineOutcome.ok, "ok"),
            (WidgetTimelineOutcome.empty, "empty"),
            (WidgetTimelineOutcome.fetchFailed, "fetch_failed"),
        ]
    )
    func outcomeWireValuesAreStable(outcome: WidgetTimelineOutcome, expected: String) {
        #expect(outcome.rawValue == expected)
    }
}
