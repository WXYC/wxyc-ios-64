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

import Foundation
import Testing
@testable import Analytics

@Suite("StructuredPostHogAnalytics concurrency safety")
struct StructuredPostHogAnalyticsConcurrencyTests {

    private struct ConcurrencyProbeEvent: AnalyticsEvent {
        static let name = "concurrency_probe_event"
        let index: Int
        var properties: [String: Any]? { ["index": index] }
    }

    @Test("N concurrent captures from the same instance all land, correctly stamped")
    func concurrentCapturesAllLand() async {
        let captured = LockedCapturingPostHogClient()
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

/// Thread-safe recording double for `PostHogClientProtocol`, guarded by an
/// `NSLock` so this test exercises `StructuredPostHogAnalytics`'s own
/// concurrency safety rather than racing on the recorder itself.
private final class LockedCapturingPostHogClient: PostHogClientProtocol, @unchecked Sendable {
    struct Captured {
        let name: String
        let properties: [String: Any]?
    }

    private let lock = NSLock()
    private var _events: [Captured] = []

    var events: [Captured] {
        lock.withLock { _events }
    }

    func capture(_ name: String, properties: [String: Any]?) {
        lock.withLock {
            _events.append(Captured(name: name, properties: properties))
        }
    }
}
