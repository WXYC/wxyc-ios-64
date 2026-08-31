//
//  TapTriggerTests.swift
//  PartyHorn
//
//  Tests the confetti burst channel, which carries tap locations from the UIKit
//  view into the hosted SwiftUI confetti view.
//
//  Created by Jake Bromberg on 08/30/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import CoreGraphics
import Testing
@testable import PartyHorn

@MainActor
@Suite("TapTrigger")
struct TapTriggerTests {

    @Test("Delivers a fired location to the burst stream")
    func deliversFiredLocation() async {
        let trigger = TapTrigger()
        var iterator = trigger.taps.makeAsyncIterator()

        trigger.fire(with: CGPoint(x: 12, y: 34))

        let received = await iterator.next()
        #expect(received == CGPoint(x: 12, y: 34))
    }

    @Test("Delivers bursts in the order they were fired")
    func deliversInOrder() async {
        let trigger = TapTrigger()
        var iterator = trigger.taps.makeAsyncIterator()

        let points = [
            CGPoint(x: 1, y: 1),
            CGPoint(x: 2, y: 2),
            CGPoint(x: 3, y: 3),
        ]
        for point in points {
            trigger.fire(with: point)
        }

        var received: [CGPoint] = []
        for _ in points {
            guard let point = await iterator.next() else { break }
            received.append(point)
        }

        #expect(received == points)
    }
}
