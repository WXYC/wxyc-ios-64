//
//  WidgetGetTimelineTests.swift
//  Analytics
//
//  Tests that the widget timeline event carries the family that asked, so
//  requests can be counted per widget size.
//
//  Created by Jake Bromberg on 08/22/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("WidgetGetTimeline event")
struct WidgetGetTimelineTests {

    @Test("Carries the requesting family")
    func carriesFamily() throws {
        let event = WidgetGetTimeline(family: "systemMedium")

        let properties = try #require(event.properties)

        #expect(properties["family"] as? String == "systemMedium")
    }
}
