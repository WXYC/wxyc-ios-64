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

/// Recording double for `PostHogClientProtocol`, shared by this suite and
/// `StructuredPostHogAnalyticsConcurrencyTests`.
///
/// Synchronized so the recorder itself can't be what races: the concurrency
/// suite hammers one instance from a task group, and the `Sendable` refinement
/// #309 put on `PostHogClientProtocol` requires conformers to mean it.
///
/// `NSLock` rather than `Mutex`, deliberately. The repo default is `Mutex`
/// (see `MockStructuredAnalytics`, #816), but that only works when the guarded
/// value is `Sendable`. `Captured.properties` is `[String: Any]?` — PostHog's
/// own property shape — so `Mutex<[Captured]>` cannot hand a snapshot back out:
/// `withLock`'s `inout sending Value` makes any value derived from the payload
/// task-isolated, and the getter fails to compile with "'inout sending'
/// parameter '$0' cannot be task-isolated at end of function". The only way to
/// reach `Mutex` here is to declare `Captured: @unchecked Sendable`, which
/// would be a worse lie than the one this annotation makes honest.
final class CapturingPostHogClient: PostHogClientProtocol, @unchecked Sendable {
    struct Captured {
        let name: String
        let properties: [String: Any]?
    }

    private let lock = NSLock()
    private var _events: [Captured] = []

    /// A snapshot of everything captured so far, in capture order.
    var events: [Captured] {
        lock.withLock { _events }
    }

    func capture(_ name: String, properties: [String: Any]?) {
        lock.withLock {
            _events.append(Captured(name: name, properties: properties))
        }
    }
}
