//
//  StructuredPostHogAnalyticsTests.swift
//  Analytics
//
//  Verifies build_type stamping on every captured event.
//
//  Created by Jake Bromberg on 06/01/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import Analytics

@Suite("StructuredPostHogAnalytics build_type stamping")
struct StructuredPostHogAnalyticsTests {

    struct PlainEvent: AnalyticsEvent {
        static let name = "plain_event"
        var properties: [String: Any]? { ["foo": "bar"] }
    }

    struct EventWithTypedBuildType: AnalyticsEvent {
        static let name = "event_with_typed_build_type"
        var properties: [String: Any]? { ["build_type": "typed_wins"] }
    }

    struct EmptyEvent: AnalyticsEvent {
        static let name = "empty_event"
        var properties: [String: Any]? { nil }
    }

    @Test("Plain event gets build_type stamped from initializer")
    func plainEventGetsBuildTypeStamped() throws {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "TestFlight")

        sut.capture(PlainEvent())

        let last = try #require(captured.events.last)
        #expect(last.name == "plain_event")
        #expect(last.properties?["foo"] as? String == "bar")
        #expect(last.properties?["build_type"] as? String == "TestFlight")
    }

    @Test("Typed event property wins on collision with stamped build_type")
    func typedEventBuildTypeWinsOverStamp() throws {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "Release")

        sut.capture(EventWithTypedBuildType())

        let last = try #require(captured.events.last)
        #expect(last.properties?["build_type"] as? String == "typed_wins")
    }

    @Test("Empty-property event still gets build_type stamped")
    func emptyEventGetsBuildTypeStamped() throws {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "Debug")

        sut.capture(EmptyEvent())

        let last = try #require(captured.events.last)
        #expect(last.properties?["build_type"] as? String == "Debug")
    }
}

final class CapturingPostHogClient: PostHogClientProtocol {
    struct Captured {
        let name: String
        let properties: [String: Any]?
    }

    private(set) var events: [Captured] = []

    func capture(_ name: String, properties: [String: Any]?) {
        events.append(.init(name: name, properties: properties))
    }
}
