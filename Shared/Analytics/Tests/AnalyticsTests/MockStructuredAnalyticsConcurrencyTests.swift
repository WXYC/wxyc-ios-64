//
//  MockStructuredAnalyticsConcurrencyTests.swift
//  Analytics
//
//  Pins MockStructuredAnalytics as genuinely safe to share across concurrency
//  domains: many concurrent `capture` calls must all land, with no lost
//  appends and no crash from a torn array buffer (#816).
//
//  Created by Jake Bromberg on 08/10/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Analytics
import AnalyticsTesting
import Testing

@Suite("MockStructuredAnalytics concurrency safety")
struct MockStructuredAnalyticsConcurrencyTests {

    private struct ConcurrencyProbeEvent: AnalyticsEvent {
        static let name = "concurrency_probe_event"
        let index: Int
        var properties: [String: Any]? { ["index": index] }
    }

    @Test("N concurrent captures all land")
    func concurrentCapturesAllLand() async {
        let mock = MockStructuredAnalytics()
        let iterations = 1000

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<iterations {
                group.addTask {
                    mock.capture(ConcurrencyProbeEvent(index: index))
                }
            }
        }

        #expect(mock.events.count == iterations)
        #expect(mock.capturedEventNames().count == iterations)
    }
}
