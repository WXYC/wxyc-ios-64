//
//  WidgetGetTimelineTests.swift
//  Analytics
//
//  Tests that the widget timeline event carries the refresh decision it made,
//  so the reload budget can be observed in production rather than reasoned
//  about from the tier table alone.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("WidgetGetTimeline event")
struct WidgetGetTimelineTests {

    @Test("Carries the family and the resolved refresh interval")
    func carriesRefreshDecision() throws {
        // Without the interval, a PostHog query can count how often the widget
        // asked for a timeline but not how much budget those requests cost,
        // which is the number this whole change is trying to move.
        let event = WidgetGetTimeline(
            family: "systemMedium",
            refreshIntervalMinutes: 15
        )

        let properties = try #require(event.properties)

        #expect(properties["family"] as? String == "systemMedium")
        #expect(properties["refresh_interval_minutes"] as? Int == 15)
    }
}
