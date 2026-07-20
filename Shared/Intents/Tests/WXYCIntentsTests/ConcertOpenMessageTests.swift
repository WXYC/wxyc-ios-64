//
//  ConcertOpenMessageTests.swift
//  WXYCIntents
//
//  Verifies the typed NotificationCenter delivery channel that carries "open
//  this On Tour show" intents from the universal-link / scheme handler in
//  AppLifecycleModifier to the On Tour tab observer (#537).
//
//  Created by Jake Bromberg on 07/20/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Testing
@testable import WXYCIntents

@Suite("ConcertOpenMessage")
struct ConcertOpenMessageTests {
    @Test("post + observe round-trips the concert id and source", arguments: [
        ConcertOpenMessage.Source.universalLink,
        ConcertOpenMessage.Source.scheme,
    ])
    @MainActor
    func roundTripsConcert(_ source: ConcertOpenMessage.Source) async throws {
        let center = NotificationCenter()
        // `queue: nil` delivers the observer synchronously on the poster's
        // thread, so the round-trip is race-free without a Task/AsyncStream
        // dance. The typed `makeMessage` still decodes the payload, so this
        // exercises the full parse path.
        let received: ConcertOpenMessage = await withCheckedContinuation { continuation in
            let observer = center.addObserver(
                forName: ConcertOpenMessage.name,
                object: nil,
                queue: nil
            ) { notification in
                if let message = ConcertOpenMessage.makeMessage(notification) {
                    continuation.resume(returning: message)
                }
            }
            _ = observer
            center.post(ConcertOpenMessage(concertID: 4821, source: source), subject: nil)
        }

        #expect(received.concertID == 4821)
        #expect(received.source == source)
    }

    @Test("makeMessage returns nil for a notification with the wrong name")
    func rejectsUnrelatedNotificationName() {
        let notification = Notification(
            name: Notification.Name("some.other.notification"),
            object: nil,
            userInfo: ["concertID": 4821, "source": "scheme"]
        )

        #expect(ConcertOpenMessage.makeMessage(notification) == nil)
    }

    @Test("makeMessage returns nil for the right name but no payload")
    func rejectsMissingPayload() {
        let notification = Notification(
            name: ConcertOpenMessage.name,
            object: nil,
            userInfo: nil
        )

        #expect(ConcertOpenMessage.makeMessage(notification) == nil)
    }

    @Test("makeMessage returns nil for a non-integer concert id payload")
    func rejectsNonIntegerPayload() {
        let notification = Notification(
            name: ConcertOpenMessage.name,
            object: nil,
            userInfo: ["concertID": "not-a-number", "source": "scheme"]
        )

        #expect(ConcertOpenMessage.makeMessage(notification) == nil)
    }

    @Test("makeMessage returns nil when the source is present but unrecognised")
    func rejectsUnknownSource() {
        let notification = Notification(
            name: ConcertOpenMessage.name,
            object: nil,
            userInfo: ["concertID": 4821, "source": "carrier-pigeon"]
        )

        #expect(ConcertOpenMessage.makeMessage(notification) == nil)
    }

    @Test("makeMessage returns nil when the source is missing")
    func rejectsMissingSource() {
        let notification = Notification(
            name: ConcertOpenMessage.name,
            object: nil,
            userInfo: ["concertID": 4821]
        )

        #expect(ConcertOpenMessage.makeMessage(notification) == nil)
    }
}
