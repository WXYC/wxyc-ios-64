//
//  OpenMessageTests.swift
//  WXYCIntents
//
//  Exercises the shared `makeMessage`/`makeNotification` default that
//  `ConcertOpenMessage`, `VenueOpenMessage`, and `PlaycutOpenMessage` all
//  inherit from `OpenMessage`, independent of any single concrete type, so a
//  regression in the shared plumbing itself (not just one conformance) shows
//  up here. Also covers the `postOpenMessage` helper every `Open*` intent's
//  `perform()` calls.
//
//  Created by Jake Bromberg on 08/06/26.
//  Copyright © 2026 WXYC. All rights reserved.
//

import Foundation
import Testing
@testable import WXYCIntents

/// A minimal `OpenMessage` conformance used only by this test suite, kept
/// separate from the three production message types so these tests fail for
/// the shared protocol's own reasons rather than incidentally exercising a
/// production type's `Payload`.
private struct FixtureOpenMessage: OpenMessage {
    typealias Subject = NSObject

    struct Payload: NotificationPayload {
        let value: String

        static func makePayload(userInfo: [AnyHashable: Any]?) -> Self? {
            guard let value = userInfo?["fixtureValue"] as? String else { return nil }
            return Self(value: value)
        }

        var userInfoEntries: [AnyHashable: Any] {
            ["fixtureValue": value]
        }
    }

    static let name = Notification.Name("org.wxyc.iphoneapp.test.fixtureOpenMessage")

    let payload: Payload

    init(payload: Payload) {
        self.payload = payload
    }

    init(value: String) {
        self.payload = Payload(value: value)
    }
}

@Suite("OpenMessage")
struct OpenMessageTests {
    @Test("makeNotification + makeMessage round-trips the payload")
    @MainActor
    func roundTripsPayload() {
        let notification = FixtureOpenMessage.makeNotification(
            FixtureOpenMessage(value: "la paradoja"),
            object: nil
        )

        let decoded = FixtureOpenMessage.makeMessage(notification)

        #expect(decoded?.payload.value == "la paradoja")
    }

    @Test("makeNotification stamps the message's own name")
    @MainActor
    func makeNotificationUsesMessageName() {
        let notification = FixtureOpenMessage.makeNotification(
            FixtureOpenMessage(value: "la paradoja"),
            object: nil
        )

        #expect(notification.name == FixtureOpenMessage.name)
    }

    @Test("makeMessage returns nil for a notification with the wrong name")
    func rejectsUnrelatedNotificationName() {
        let notification = Notification(
            name: Notification.Name("some.other.notification"),
            object: nil,
            userInfo: ["fixtureValue": "la paradoja"]
        )

        #expect(FixtureOpenMessage.makeMessage(notification) == nil)
    }

    @Test("makeMessage returns nil when the payload fails to decode")
    func rejectsUndecodablePayload() {
        let notification = Notification(
            name: FixtureOpenMessage.name,
            object: nil,
            userInfo: nil
        )

        #expect(FixtureOpenMessage.makeMessage(notification) == nil)
    }

    @Test("postOpenMessage posts to NotificationCenter.default with no subject")
    @MainActor
    func postOpenMessagePostsToDefaultCenter() async throws {
        var observer: NSObjectProtocol?
        let received: FixtureOpenMessage = await withCheckedContinuation { continuation in
            observer = NotificationCenter.default.addObserver(
                forName: FixtureOpenMessage.name,
                object: nil,
                queue: nil
            ) { notification in
                if let message = FixtureOpenMessage.makeMessage(notification) {
                    continuation.resume(returning: message)
                }
            }
            postOpenMessage(FixtureOpenMessage(value: "Stereolab"))
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }

        #expect(received.payload.value == "Stereolab")
    }
}
