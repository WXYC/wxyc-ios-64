//
//  VenueOpenMessageTests.swift
//  WXYCIntents
//
//  Verifies the typed NotificationCenter delivery channel that carries "open
//  this venue's shows" requests from `OpenVenue.perform()` to the On Tour
//  tab's venue-filter observer (OT-C4), mirroring ConcertOpenMessageTests.
//
//  Created by Jake Bromberg on 07/24/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Testing
@testable import WXYCIntents

@Suite("VenueOpenMessage")
struct VenueOpenMessageTests {
    @Test("post + observe round-trips the venue id")
    @MainActor
    func roundTripsVenueID() async throws {
        let center = NotificationCenter()
        // `queue: nil` delivers the observer synchronously on the poster's
        // thread, so the round-trip is race-free without a Task/AsyncStream
        // dance, mirroring ConcertOpenMessageTests.
        let received: VenueOpenMessage = await withCheckedContinuation { continuation in
            let observer = center.addObserver(
                forName: VenueOpenMessage.name,
                object: nil,
                queue: nil
            ) { notification in
                if let message = VenueOpenMessage.makeMessage(notification) {
                    continuation.resume(returning: message)
                }
            }
            _ = observer
            center.post(VenueOpenMessage(venueID: 3), subject: nil)
        }

        #expect(received.venueID == 3)
    }

    @Test("makeMessage returns nil for a notification with the wrong name")
    func rejectsUnrelatedNotificationName() {
        let notification = Notification(
            name: Notification.Name("some.other.notification"),
            object: nil,
            userInfo: ["venueID": 3]
        )

        #expect(VenueOpenMessage.makeMessage(notification) == nil)
    }

    @Test("makeMessage returns nil for the right name but no payload")
    func rejectsMissingPayload() {
        let notification = Notification(
            name: VenueOpenMessage.name,
            object: nil,
            userInfo: nil
        )

        #expect(VenueOpenMessage.makeMessage(notification) == nil)
    }

    @Test("makeMessage returns nil for a non-integer venue id payload")
    func rejectsNonIntegerPayload() {
        let notification = Notification(
            name: VenueOpenMessage.name,
            object: nil,
            userInfo: ["venueID": "not-a-number"]
        )

        #expect(VenueOpenMessage.makeMessage(notification) == nil)
    }
}
