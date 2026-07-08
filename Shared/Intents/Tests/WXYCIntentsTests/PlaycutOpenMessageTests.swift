//
//  PlaycutOpenMessageTests.swift
//  WXYCIntents
//
//  Verifies the typed NotificationCenter delivery channel that carries "open
//  this playcut" intents between the URL scheme handler and the F3 consumer.
//  Because delivery is @MainActor, the suite itself is @MainActor.
//
//  Created by Jake Bromberg on 07/08/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Core
import Foundation
import Testing
@testable import WXYCIntents

@MainActor
@Suite("PlaycutOpenMessage")
struct PlaycutOpenMessageTests {
    @Test("post + observe round-trips the typed playcut id")
    func roundTripsPlaycutID() async throws {
        let center = NotificationCenter()
        var received: PlaycutID?
        let token = center.addMainActorObserver(for: PlaycutOpenMessage.self) { message in
            received = message.playcutID
        }
        defer { center.removeObserver(token) }

        center.post(PlaycutOpenMessage(playcutID: PlaycutID(42)), subject: nil)

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
