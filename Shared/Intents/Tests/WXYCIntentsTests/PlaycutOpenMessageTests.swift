//
//  PlaycutOpenMessageTests.swift
//  WXYCIntents
//
//  Verifies the typed NotificationCenter delivery channel that carries "open
//  this playcut" intents between the URL scheme handler and the F3 consumer.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Testing
@testable import WXYCIntents

@Suite("PlaycutOpenMessage")
struct PlaycutOpenMessageTests {
    @Test("post + observe round-trips the typed playcut id")
    @MainActor
    func roundTripsPlaycutID() async throws {
        let center = NotificationCenter()
        // `queue: nil` delivers the observer synchronously on the poster's
        // thread, which makes the round-trip race-free without needing a
        // Task/AsyncStream dance. The typed `makeMessage` is still what
        // decodes the payload, so this exercises the full parse path.
        let received: PlaycutID = await withCheckedContinuation { continuation in
            let observer = center.addObserver(
                forName: PlaycutOpenMessage.name,
                object: nil,
                queue: nil
            ) { notification in
                if let message = PlaycutOpenMessage.makeMessage(notification) {
                    continuation.resume(returning: message.playcutID)
                }
            }
            _ = observer
            center.post(PlaycutOpenMessage(playcutID: PlaycutID(42)), subject: nil)
        }

        #expect(received == PlaycutID(42))
    }

    @Test("makeMessage returns nil for a notification with the wrong name")
    func rejectsUnrelatedNotificationName() {
        let notification = Notification(
            name: Notification.Name("some.other.notification"),
            object: nil,
            userInfo: ["playcutID": "42"]
        )

        #expect(PlaycutOpenMessage.makeMessage(notification) == nil)
    }

    @Test("makeMessage returns nil for the right name but no payload")
    func rejectsMissingPayload() {
        let notification = Notification(
            name: PlaycutOpenMessage.name,
            object: nil,
            userInfo: nil
        )

        #expect(PlaycutOpenMessage.makeMessage(notification) == nil)
    }

    @Test("makeMessage returns nil for a non-numeric playcut id string")
    func rejectsNonNumericPayload() {
        let notification = Notification(
            name: PlaycutOpenMessage.name,
            object: nil,
            userInfo: ["playcutID": "not-a-number"]
        )

        #expect(PlaycutOpenMessage.makeMessage(notification) == nil)
    }
}
