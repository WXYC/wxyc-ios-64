//
//  StructuredPostHogAnalyticsConcurrencyTests.swift
//  Analytics
//
//  Pins StructuredPostHogAnalytics as genuinely safe to share across
//  concurrency domains: many concurrent `capture` calls against the same
//  `.shared`-shaped instance must all land, correctly stamped, with no lost
//  or corrupted writes (#309 — struct conversion away from `@unchecked
//  Sendable`).
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Testing
@testable import Analytics

@Suite("StructuredPostHogAnalytics concurrency safety")
struct StructuredPostHogAnalyticsConcurrencyTests {

    @Test("N concurrent captures from the same instance all land, correctly stamped")
    func concurrentCapturesAllLand() async {
        let captured = CapturingPostHogClient()
        let sut = StructuredPostHogAnalytics(client: captured, buildType: "TestFlight")
        let iterations = 1000

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<iterations {
                group.addTask {
                    sut.capture(ConcurrencyProbeEvent(index: index))
                }
            }
        }

        let events = captured.events
        #expect(events.count == iterations)

        let indices = Set(events.compactMap { $0.properties?["index"] as? Int })
        #expect(indices.count == iterations, "every index 0..<\(iterations) should appear exactly once")
        #expect(events.allSatisfy { $0.properties?["build_type"] as? String == "TestFlight" })
    }
}

// MARK: - Test Doubles

private struct ConcurrencyProbeEvent: AnalyticsEvent {
    static let name = "concurrency_probe_event"
    let index: Int
    var properties: [String: Any]? { ["index": index] }
}
