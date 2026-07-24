//
//  OpenVenueTests.swift
//  WXYCIntents
//
//  Verifies OpenVenue.perform() posts a VenueOpenMessage carrying the target
//  entity's backend id — the message Singletonia observes to narrow the On
//  Tour tab's venue filter down to this venue's shows (OT-C4), mirroring
//  OpenConcertTests.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
import Concerts
import ConcertsTesting
@testable import WXYCIntents

@Suite("OpenVenue")
struct OpenVenueTests {
    @Test("perform() posts a VenueOpenMessage with the target's id")
    @MainActor
    func performPostsVenueOpenMessage() async throws {
        let entity = try #require(VenueEntity(venue: .stub(id: 3)))
        let intent = OpenVenue(target: entity)

        // `queue: nil` delivers the observer synchronously on the poster's
        // thread, race-free without polling — mirroring OpenConcertTests.
        // This necessarily posts through the shared `NotificationCenter.default`
        // because that's what `perform()` uses; the observer is torn down
        // before this test returns.
        var observer: NSObjectProtocol?
        let received: VenueOpenMessage = await withCheckedContinuation { continuation in
            observer = NotificationCenter.default.addObserver(
                forName: VenueOpenMessage.name,
                object: nil,
                queue: nil
            ) { notification in
                if let message = VenueOpenMessage.makeMessage(notification) {
                    continuation.resume(returning: message)
                }
            }
            Task {
                _ = try? await intent.perform()
            }
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }

        #expect(received.venueID == 3)
    }
}
